//===- RegisterClearingTest.cpp --------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "../../lib/CodeGen/RegisterClearing.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/TargetInstrInfo.h"
#include "llvm/CodeGen/TargetRegisterInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
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
struct ClearingTarget {
  const char *Name;
  const char *Triple;
  const char *Features;
  const char *ReturnOpcode;
  const char *ClearOpcode;
  const char *Scratch;
  const char *Candidate;
  const char *ReturnValue;
  const char *FullReturnValue;
  const char *Reserved;
  const char *CalleeSaved;
  const char *Unsupported;
  const char *Partial;
};

class RegisterClearingTest : public testing::TestWithParam<ClearingTarget> {
protected:
  LLVMContext Context;
  std::unique_ptr<TargetMachine> TM;
  std::unique_ptr<Module> Mod;
  std::unique_ptr<MachineModuleInfo> MMI;
  MachineFunction *MF = nullptr;
  const TargetRegisterInfo *TRI = nullptr;
  const TargetInstrInfo *TII = nullptr;
  std::string Diagnostics;
  unsigned Errors = 0;

  static void SetUpTestSuite() {
    InitializeAllTargetInfos();
    InitializeAllTargets();
    InitializeAllTargetMCs();
  }

  void SetUp() override {
    Triple TT(GetParam().Triple);
    std::string Error;
    const Target *T = TargetRegistry::lookupTarget(TT, Error);
    if (!T)
      GTEST_SKIP() << Error;
    TM.reset(T->createTargetMachine(TT, "", GetParam().Features,
                                    TargetOptions(), std::nullopt));
    ASSERT_NE(TM, nullptr);
    Mod = std::make_unique<Module>("clearing", Context);
    Mod->setDataLayout(TM->createDataLayout());
    auto *F =
        Function::Create(FunctionType::get(Type::getVoidTy(Context), false),
                         GlobalValue::ExternalLinkage, "test", *Mod);
    ReturnInst::Create(Context, BasicBlock::Create(Context, "entry", F));
    F->addFnAttr("zeroize-stack", "used");
    MMI = std::make_unique<MachineModuleInfo>(TM.get());
    MF = &MMI->getOrCreateMachineFunction(*F);
    MF->getProperties().set(MachineFunctionProperties::Property::NoVRegs);
    MF->getRegInfo().freezeReservedRegs();
    TRI = MF->getSubtarget().getRegisterInfo();
    TII = MF->getSubtarget().getInstrInfo();
    Context.setDiagnosticHandlerCallBack(
        [](const DiagnosticInfo *DI, void *Opaque) {
          auto &Self = *static_cast<RegisterClearingTest *>(Opaque);
          raw_string_ostream OS(Self.Diagnostics);
          DiagnosticPrinterRawOStream Printer(OS);
          DI->print(Printer);
          Self.Errors += DI->getSeverity() == DS_Error;
        },
        this);
  }

  MCRegister reg(StringRef Name) {
    for (unsigned I = 1; I != TRI->getNumRegs(); ++I)
      if (Name == TRI->getName(I))
        return MCRegister(I);
    ADD_FAILURE() << "Unknown register " << Name.str();
    return MCRegister();
  }

  unsigned opcode(StringRef Name) {
    for (unsigned I = 0; I != TII->getNumOpcodes(); ++I)
      if (Name == TII->getName(I))
        return I;
    ADD_FAILURE() << "Unknown opcode " << Name.str();
    return 0;
  }

  MachineBasicBlock &addExit() {
    auto *MBB = MF->CreateMachineBasicBlock();
    MF->push_back(MBB);
    auto Ret = BuildMI(*MBB, MBB->end(), DebugLoc(),
                       TII->get(opcode(GetParam().ReturnOpcode)));
    if (TM->getTargetTriple().isX86())
      Ret.addImm(0);
    Ret.addReg(reg(GetParam().ReturnValue), RegState::Implicit);
    return *MBB;
  }

  BitVector regs(std::initializer_list<MCRegister> Registers) {
    BitVector Result(TRI->getNumRegs());
    for (MCRegister Reg : Registers)
      Result.set(Reg);
    return Result;
  }

  bool clear(MachineBasicBlock &MBB, const BitVector &Candidates,
             const BitVector &Scratch) {
    return emitZeroCallUsedRegsWithScratch(Candidates, Scratch, MBB,
                                           MBB.getFirstTerminator(), nullptr);
  }

  void expectClears(MachineBasicBlock &MBB,
                    std::initializer_list<MCRegister> Expected) {
    EXPECT_EQ(MBB.size(), Expected.size() + 1);
    for (MCRegister Reg : Expected) {
      unsigned Count = 0;
      for (auto I = MBB.begin(), E = MBB.getFirstTerminator(); I != E; ++I) {
        EXPECT_EQ(I->getOpcode(), opcode(GetParam().ClearOpcode));
        EXPECT_FALSE(I->modifiesRegister(reg(GetParam().ReturnValue), TRI));
        for (const MachineOperand &MO : I->explicit_operands())
          if (MO.isImm())
            EXPECT_EQ(MO.getImm(), 0);
        if (TM->getTargetTriple().isX86()) {
          EXPECT_EQ(I->getOperand(0).getReg(), I->getOperand(1).getReg());
          EXPECT_EQ(I->getOperand(0).getReg(), I->getOperand(2).getReg());
        }
        Count += I->modifiesRegister(Reg, TRI);
      }
      EXPECT_EQ(Count, 1u);
    }
    EXPECT_EQ(Errors, 0u) << Diagnostics;
  }

  void expectRejected(MCRegister Reg) {
    auto &MBB = addExit();
    unsigned PreviousErrors = Errors;
    EXPECT_FALSE(clear(MBB, regs({}), regs({Reg})));
    EXPECT_EQ(MBB.size(), 1u);
    EXPECT_EQ(Errors, PreviousErrors + 1);
  }
};

TEST_P(RegisterClearingTest, ScratchWithoutRegisterAttribute) {
  auto &MBB = addExit();
  MCRegister Scratch = reg(GetParam().Scratch);
  ASSERT_TRUE(clear(MBB, regs({}), regs({Scratch})));
  expectClears(MBB, {Scratch});
}

TEST_P(RegisterClearingTest, ScratchWithSkip) {
  MF->getFunction().addFnAttr("zero-call-used-regs", "skip");
  auto &MBB = addExit();
  MCRegister Scratch = reg(GetParam().Scratch);
  ASSERT_TRUE(clear(MBB, regs({}), regs({Scratch})));
  expectClears(MBB, {Scratch});
}

TEST_P(RegisterClearingTest, ScratchAddedToFilteredCandidates) {
  MF->getFunction().addFnAttr("zero-call-used-regs", "used-gpr");
  auto &MBB = addExit();
  MCRegister Scratch = reg(GetParam().Scratch);
  MCRegister Candidate = reg(GetParam().Candidate);
  ASSERT_TRUE(clear(MBB, regs({Candidate}), regs({Scratch})));
  expectClears(MBB, {Candidate, Scratch});
}

TEST_P(RegisterClearingTest, DuplicateRegisterClearedOnce) {
  auto &MBB = addExit();
  MCRegister Scratch = reg(GetParam().Scratch);
  ASSERT_TRUE(clear(MBB, regs({Scratch}), regs({Scratch})));
  expectClears(MBB, {Scratch});
}

TEST_P(RegisterClearingTest, IndependentExitDeclarations) {
  auto &First = addExit();
  auto &Second = addExit();
  MCRegister A = reg(GetParam().Scratch);
  MCRegister B = reg(GetParam().Candidate);
  ASSERT_TRUE(clear(First, regs({}), regs({A})));
  ASSERT_TRUE(clear(Second, regs({}), regs({B})));
  expectClears(First, {A});
  expectClears(Second, {B});
}

TEST_P(RegisterClearingTest, EmptyScratchLeavesOnlyCandidates) {
  auto &MBB = addExit();
  MCRegister Candidate = reg(GetParam().Candidate);
  ASSERT_TRUE(clear(MBB, regs({Candidate}), regs({})));
  expectClears(MBB, {Candidate});
}

TEST_P(RegisterClearingTest, ReservedRegisterRejected) {
  expectRejected(reg(GetParam().Reserved));
  EXPECT_THAT(Diagnostics, HasSubstr("not supported for scratch"));
}

TEST_P(RegisterClearingTest, InvalidScratchPreventsCandidateClearing) {
  auto &MBB = addExit();
  EXPECT_FALSE(clear(MBB, regs({reg(GetParam().Candidate)}),
                     regs({reg(GetParam().Unsupported)})));
  EXPECT_EQ(MBB.size(), 1u);
  EXPECT_EQ(Errors, 1u);
}

TEST_P(RegisterClearingTest, LiveReturnRejected) {
  expectRejected(reg(GetParam().FullReturnValue));
  EXPECT_THAT(Diagnostics, HasSubstr("needed at the exit"));
}

TEST_P(RegisterClearingTest, CalleeSavedRegisterRejected) {
  expectRejected(reg(GetParam().CalleeSaved));
}

TEST_P(RegisterClearingTest, UpdatedCalleeSavedRegisterRejected) {
  // Call lowering can extend the target's base CSR list, for example for
  // AArch64's +call-saved-x9 feature.
  SmallVector<MCPhysReg> CSRs;
  for (const MCPhysReg *CSR = MF->getRegInfo().getCalleeSavedRegs(); *CSR;
       ++CSR)
    CSRs.push_back(*CSR);
  MCRegister Scratch = reg(GetParam().Scratch);
  CSRs.push_back(Scratch);
  MF->getRegInfo().setCalleeSavedRegs(CSRs);
  expectRejected(Scratch);
  EXPECT_THAT(Diagnostics, HasSubstr("needed at the exit"));
}

TEST_P(RegisterClearingTest, PartialRegisterRejected) {
  // AH is disjoint from the live AL return, but XOR32rr would overwrite AL.
  expectRejected(reg(GetParam().Partial));
  EXPECT_THAT(Diagnostics, HasSubstr("not supported for scratch"));
}

TEST_P(RegisterClearingTest, UnsupportedRegisterRejected) {
  expectRejected(reg(GetParam().Unsupported));
  EXPECT_THAT(Diagnostics, HasSubstr("not supported for scratch"));
  if (TM->getTargetTriple().isAArch64()) {
    // The emitter skips X19-X30 even when the calling convention preserves
    // none.
    for (auto CC : {CallingConv::PreserveNone, CallingConv::GHC}) {
      MF->getFunction().setCallingConv(CC);
      for (StringRef Name : {"X19", "X28", "FP"})
        expectRejected(reg(Name));
    }
  }
}

TEST_P(RegisterClearingTest, ReturnAddressRejected) {
  if (TM->getTargetTriple().isRISCV())
    // GHC preserves no registers; PseudoRET does not name the return address.
    MF->getFunction().setCallingConv(CallingConv::GHC);
  expectRejected(TRI->getRARegister());
}

INSTANTIATE_TEST_SUITE_P(
    Targets, RegisterClearingTest,
    testing::Values(ClearingTarget{"X86_64", "x86_64-linux-gnu", "+mmx",
                                   "RET64", "XOR32rr", "R11", "R10", "AL",
                                   "RAX", "RSP", "RBX", "MM0", "AH"},
                    ClearingTarget{"X86_32", "i386-linux-gnu", "+mmx", "RET32",
                                   "XOR32rr", "ECX", "EDX", "AL", "EAX", "ESP",
                                   "EBX", "MM0", "AH"},
                    ClearingTarget{"AArch64", "aarch64-linux-gnu", "",
                                   "RET_ReallyLR", "MOVZXi", "X9", "X10", "W0",
                                   "X0", "SP", "X19", "D9", "W9"},
                    ClearingTarget{"RISCV32", "riscv32-linux-gnu", "+d",
                                   "PseudoRET", "PseudoClearGPR", "X5", "X6",
                                   "X10", "X10", "X2", "X9", "V0", "X5_H"},
                    ClearingTarget{"RISCV64", "riscv64-linux-gnu", "+d",
                                   "PseudoRET", "PseudoClearGPR", "X5", "X6",
                                   "X10", "X10", "X2", "X9", "V0", "X5_H"}),
    [](const testing::TestParamInfo<ClearingTarget> &Info) {
      return Info.param.Name;
    });
} // namespace
