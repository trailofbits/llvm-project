//===- X86RegisterClearingTest.cpp --------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// The call-used register clearing on X86 clears every register it is asked
// for or reports the ones it cannot. These tests ask for the whole set the
// prologue/epilogue inserter can build on a range of subtargets and check that
// nothing is dropped in between.
//
//===----------------------------------------------------------------------===//

#include "X86InstrInfo.h"
#include "X86RegisterInfo.h"
#include "X86Subtarget.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/TargetFrameLowering.h"
#include "llvm/IR/DiagnosticInfo.h"
#include "llvm/IR/DiagnosticPrinter.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/IR/Module.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Target/TargetMachine.h"
#include "gmock/gmock.h"
#include "gtest/gtest.h"

using namespace llvm;
using testing::HasSubstr;

namespace {
struct ClearingSubtarget {
  const char *Triple;
  const char *Features;
  /// Registers the subtarget can write but cannot clear, which the emitter
  /// must report. Null when every requested register is clearable.
  const char *Uncleared;
};

class X86RegisterClearingTest
    : public testing::TestWithParam<ClearingSubtarget> {
protected:
  LLVMContext Context;
  std::unique_ptr<TargetMachine> TM;
  std::unique_ptr<Module> Mod;
  std::unique_ptr<MachineModuleInfo> MMI;
  MachineFunction *MF = nullptr;
  const X86Subtarget *STI = nullptr;
  const X86RegisterInfo *TRI = nullptr;
  const X86InstrInfo *TII = nullptr;
  std::string Diagnostics;
  unsigned Errors = 0;

  static void SetUpTestSuite() {
    LLVMInitializeX86TargetInfo();
    LLVMInitializeX86Target();
    LLVMInitializeX86TargetMC();
  }

  void SetUp() override {
    Triple TT(GetParam().Triple);
    std::string Error;
    const Target *T = TargetRegistry::lookupTarget(TT, Error);
    ASSERT_NE(T, nullptr) << Error;
    TM.reset(T->createTargetMachine(TT, "", GetParam().Features,
                                    TargetOptions(), std::nullopt));
    ASSERT_NE(TM, nullptr);
    Mod = std::make_unique<Module>("clearing", Context);
    Mod->setDataLayout(TM->createDataLayout());
    auto *F =
        Function::Create(FunctionType::get(Type::getVoidTy(Context), false),
                         GlobalValue::ExternalLinkage, "test", *Mod);
    ReturnInst::Create(Context, BasicBlock::Create(Context, "entry", F));
    F->addFnAttr("zero-call-used-regs", "all");
    MMI = std::make_unique<MachineModuleInfo>(TM.get());
    MF = &MMI->getOrCreateMachineFunction(*F);
    MF->getProperties().set(MachineFunctionProperties::Property::NoVRegs);
    MF->getRegInfo().freezeReservedRegs();
    STI = &MF->getSubtarget<X86Subtarget>();
    TRI = STI->getRegisterInfo();
    TII = STI->getInstrInfo();
    Context.setDiagnosticHandlerCallBack(
        [](const DiagnosticInfo *DI, void *Opaque) {
          auto &Self = *static_cast<X86RegisterClearingTest *>(Opaque);
          raw_string_ostream OS(Self.Diagnostics);
          DiagnosticPrinterRawOStream Printer(OS);
          DI->print(Printer);
          Self.Errors += DI->getSeverity() == DS_Error;
        },
        this);
  }

  /// A block that leaves through \p ExitOpcode, a return unless told otherwise.
  MachineBasicBlock &addExit(unsigned ExitOpcode = 0) {
    auto *MBB = MF->CreateMachineBasicBlock();
    MF->push_back(MBB);
    if (ExitOpcode == 0) {
      ExitOpcode = STI->is64Bit() ? X86::RET64 : X86::RET32;
      BuildMI(*MBB, MBB->end(), DebugLoc(), TII->get(ExitOpcode)).addImm(0);
    } else {
      BuildMI(*MBB, MBB->end(), DebugLoc(), TII->get(ExitOpcode));
    }
    return *MBB;
  }

  /// The widest set the prologue/epilogue inserter builds: every allocatable
  /// register that is not fixed, callee-saved, or the return address.
  BitVector requestedSet() {
    BitVector Set = TRI->getAllocatableSet(*MF);
    for (MCRegister Reg : Set.set_bits())
      if (TRI->isFixedRegister(*MF, Reg))
        Set.reset(Reg);
    for (const MCPhysReg *CSRegs = TRI->getCalleeSavedRegs(MF);
         MCPhysReg CSReg = *CSRegs; ++CSRegs)
      for (MCRegister Reg : TRI->sub_and_superregs_inclusive(CSReg))
        Set.reset(Reg.id());
    if (MCRegister RAReg = TRI->getRARegister())
      for (MCRegister Reg : TRI->sub_and_superregs_inclusive(RAReg))
        Set.reset(Reg.id());
    return Set;
  }

  BitVector regs(std::initializer_list<MCRegister> Registers) {
    BitVector Result(TRI->getNumRegs());
    for (MCRegister Reg : Registers)
      Result.set(Reg);
    return Result;
  }

  /// Emit the clear at the exit: in front of the terminator, or in front of
  /// the last instruction when the exit is not one, as the coordinator does
  /// for an exit that leaves through a call.
  void clear(MachineBasicBlock &MBB, const BitVector &Set) {
    const TargetFrameLowering &TFI = *STI->getFrameLowering();
    MachineBasicBlock::iterator Exit = MBB.getFirstTerminator();
    if (Exit == MBB.end())
      Exit = std::prev(MBB.end());
    TFI.emitZeroCallUsedRegs(Set, MBB, Exit, nullptr);
  }

  unsigned count(const MachineBasicBlock &MBB, unsigned Opcode) {
    return llvm::count_if(MBB, [&](const MachineInstr &MI) {
      return MI.getOpcode() == Opcode;
    });
  }

  /// Whether an emitted instruction writes \p Reg or a register overlapping
  /// it. The x87 fill has no register operands and is checked by count.
  bool cleared(const MachineBasicBlock &MBB, MCRegister Reg) {
    for (const MachineInstr &MI : MBB) {
      if (MI.isTerminator() || MI.getOpcode() == X86::MMX_EMMS)
        continue;
      if (MI.modifiesRegister(Reg, TRI))
        return true;
    }
    return false;
  }

  /// Whether a diagnostic names \p Reg, as one entry of its quoted list.
  bool reported(MCRegister Reg) {
    std::string Name = TRI->getName(Reg);
    for (const char *Before : {"'", ", "})
      for (const char *After : {"'", ","})
        if (Diagnostics.find(Before + Name + After) != std::string::npos)
          return true;
    return false;
  }

  bool hasX87AndMMX() const {
    return STI->hasX87() && !STI->useSoftFloat() && STI->hasMMX();
  }
};

TEST_P(X86RegisterClearingTest, EveryRequestedRegisterClearedOrReported) {
  auto &MBB = addExit();
  BitVector Set = requestedSet();

  // These never reach the emitter, and it says so; keep that true.
  EXPECT_FALSE(Set.test(X86::TMM0));
  EXPECT_FALSE(Set.test(X86::K0_K1));
  EXPECT_FALSE(Set.test(X86::ST0));
  EXPECT_FALSE(Set.test(X86::FP7));

  clear(MBB, Set);

  const bool X87Filled = count(MBB, X86::LD_F0) == 8;
  EXPECT_EQ(count(MBB, X86::LD_F0), count(MBB, X86::ST_FPrr));
  for (MCRegister Reg : Set.set_bits()) {
    bool IsX87 = X86::RFP80RegClass.contains(Reg) ||
                 X86::VR64RegClass.contains(Reg);
    EXPECT_TRUE((IsX87 && X87Filled) || cleared(MBB, Reg) || reported(Reg))
        << "register " << TRI->getName(Reg) << " neither cleared nor reported";
  }

  if (const char *Uncleared = GetParam().Uncleared) {
    EXPECT_EQ(Errors, 1u) << Diagnostics;
    EXPECT_THAT(Diagnostics, HasSubstr(Uncleared));
    EXPECT_THAT(Diagnostics, HasSubstr("no instruction to clear"));
  } else {
    EXPECT_EQ(Errors, 0u) << Diagnostics;
  }
}

TEST_P(X86RegisterClearingTest, X87DepthUnknownIsAnError) {
  if (!hasX87AndMMX())
    GTEST_SKIP() << "needs x87 and MMX";
  // A trap does not record the live x87 stack, so the fill cannot be sized.
  auto &MBB = addExit(X86::TRAP);
  MCRegister GPR = STI->is64Bit() ? X86::RAX : X86::EAX;
  clear(MBB, regs({X86::FP0, X86::MM0, GPR}));

  EXPECT_EQ(Errors, 1u) << Diagnostics;
  EXPECT_THAT(Diagnostics, HasSubstr("stack depth is unknown"));
  EXPECT_EQ(count(MBB, X86::LD_F0), 0u);
  EXPECT_EQ(count(MBB, X86::MMX_EMMS), 0u);
  // The report does not suppress the rest of the clear.
  EXPECT_TRUE(cleared(MBB, GPR));
}

TEST_P(X86RegisterClearingTest, MMXUseEmptiesTheStackFirst) {
  if (!hasX87AndMMX())
    GTEST_SKIP() << "needs x87 and MMX";

  // No MMX write anywhere in the function: the stack is empty at a return.
  auto &Plain = addExit();
  clear(Plain, regs({X86::MM0}));
  EXPECT_EQ(count(Plain, X86::MMX_EMMS), 0u);
  EXPECT_EQ(count(Plain, X86::LD_F0), 8u);
  EXPECT_EQ(count(Plain, X86::ST_FPrr), 8u);

  // An MMX write leaves every x87 slot marked valid, so the fill is preceded
  // by emms. The clear at the other exit is not an MMX write.
  auto &Written = addExit();
  BuildMI(Written, Written.getFirstTerminator(), DebugLoc(),
          TII->get(X86::MMX_PXORrr), X86::MM0)
      .addReg(X86::MM0, RegState::Undef)
      .addReg(X86::MM0, RegState::Undef);
  clear(Written, regs({X86::MM0}));
  EXPECT_EQ(count(Written, X86::MMX_EMMS), 1u);
  EXPECT_EQ(count(Written, X86::LD_F0), 8u);
  auto EMMS = llvm::find_if(Written, [](const MachineInstr &MI) {
    return MI.getOpcode() == X86::MMX_EMMS;
  });
  ASSERT_NE(EMMS, Written.end());
  EXPECT_EQ(std::next(EMMS)->getOpcode(), X86::LD_F0);
  EXPECT_EQ(Errors, 0u) << Diagnostics;
}

INSTANTIATE_TEST_SUITE_P(
    Subtargets, X86RegisterClearingTest,
    testing::Values(
        ClearingSubtarget{"x86_64-unknown-linux-gnu", "", nullptr},
        ClearingSubtarget{"x86_64-unknown-linux-gnu", "+mmx", nullptr},
        ClearingSubtarget{"x86_64-unknown-linux-gnu", "+mmx,+avx", nullptr},
        ClearingSubtarget{"x86_64-unknown-linux-gnu", "+avx", nullptr},
        ClearingSubtarget{"x86_64-unknown-linux-gnu", "+avx512f", nullptr},
        ClearingSubtarget{"x86_64-unknown-linux-gnu", "+avx512f,+avx512vl",
                          nullptr},
        ClearingSubtarget{"x86_64-unknown-linux-gnu",
                          "+avx512f,+avx512bw,+avx512vl", nullptr},
        ClearingSubtarget{"x86_64-unknown-linux-gnu", "-sse,-sse2", nullptr},
        ClearingSubtarget{"x86_64-unknown-linux-gnu", "-mmx", nullptr},
        ClearingSubtarget{"x86_64-unknown-linux-gnu", "-x87,+mmx",
                          "'MM0, MM1, MM2, MM3, MM4, MM5, MM6, MM7'"},
        ClearingSubtarget{"x86_64-unknown-linux-gnu", "+amx-tile,+avx512f",
                          nullptr},
        ClearingSubtarget{"i386-unknown-linux-gnu", "", nullptr},
        ClearingSubtarget{"i386-unknown-linux-gnu", "+sse2,+mmx", nullptr},
        ClearingSubtarget{"i386-unknown-linux-gnu", "+avx512f,+avx512vl",
                          nullptr}),
    [](const testing::TestParamInfo<ClearingSubtarget> &Info) {
      std::string Name = Triple(Info.param.Triple).getArchName().str();
      for (char C : StringRef(Info.param.Features)) {
        if (C == '+')
          Name += "_with_";
        else if (C == '-')
          Name += "_without_";
        else if (isalnum(static_cast<unsigned char>(C)))
          Name += C;
        else
          Name += '_';
      }
      return Name;
    });
} // namespace
