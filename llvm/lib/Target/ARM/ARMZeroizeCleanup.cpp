//===-- ARMZeroizeCleanup.cpp - Fixed-frame EHABI clearing
//------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "ARMZeroizeCleanup.h"
#include "ARMAsmPrinter.h"
#include "ARMFrameLowering.h"
#include "ARMMachineFunctionInfo.h"
#include "ARMSubtarget.h"
#include "MCTargetDesc/ARMMCAsmInfo.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/IR/EHPersonalities.h"
#include "llvm/IR/Instructions.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCInstBuilder.h"
#include "llvm/MC/MCStreamer.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/MCSymbol.h"

using namespace llvm;

static bool hasGNUCleanupPersonality(const MachineFunction &MF) {
  const Function &F = MF.getFunction();
  return F.hasPersonalityFn() &&
         classifyEHPersonality(F.getPersonalityFn()) ==
             EHPersonality::GNU_CXX &&
         !MF.hasEHFunclets() && MF.getFilterIds().empty();
}

static bool hasIRCatchAndCleanupPads(const Function &F) {
  for (const BasicBlock &BB : F) {
    if (!BB.isEHPad())
      continue;
    const auto *LP = dyn_cast<LandingPadInst>(&*BB.getFirstNonPHIIt());
    if (!LP)
      return false;
    for (unsigned I = 0; I != LP->getNumClauses(); ++I)
      if (!LP->isCatch(I))
        return false;
  }
  return true;
}

static bool hasCatchAndCleanupPads(const MachineFunction &MF) {
  return hasGNUCleanupPersonality(MF) &&
         hasIRCatchAndCleanupPads(MF.getFunction()) &&
         llvm::all_of(MF.getLandingPads(), [](const LandingPadInfo &LP) {
           return llvm::all_of(LP.TypeIds, [](int ID) { return ID >= 0; });
         });
}

static bool hasCleanupTarget(const MachineFunction &MF) {
  const Function &F = MF.getFunction();
  const auto &STI = MF.getSubtarget<ARMSubtarget>();
  return F.hasZeroizeStack() && F.getCallingConv() == CallingConv::C &&
         STI.isTargetELF() && STI.hasV7Ops() && !STI.isMClass() &&
         !STI.isThumb1Only();
}

static bool hasCleanupLayout(const MachineFunction &MF) {
  const auto &STI = MF.getSubtarget<ARMSubtarget>();
  const auto &MFI = MF.getFrameInfo();
  return !STI.getFrameLowering()->hasFP(MF) && !MF.hasBBSections() &&
         !MFI.hasVarSizedObjects() && !MFI.hasOpaqueSPAdjustment() &&
         MFI.getMaxAlign() <= STI.getFrameLowering()->getStackAlign() &&
         !STI.getRegisterInfo()->hasStackRealignment(MF);
}

static bool hasCleanupEntryProtocol(const MachineFunction &MF) {
  const Function &F = MF.getFunction();
  return !F.hasFnAttribute(Attribute::SafeStack) && !F.isVarArg() &&
         !F.hasFnAttribute("interrupt") && !MF.shouldSplitStack() &&
         !F.hasFnAttribute("xray-instruction-threshold") &&
         F.getFnAttribute("function-instrument").getValueAsString() !=
             "xray-always";
}

static bool hasCleanupRegisters(const MachineFunction &MF) {
  // Personality helpers borrow all these registers across runtime calls.
  // Restoring a platform-reserved register on return is not sufficient.
  BitVector Reserved =
      MF.getRegInfo().reservedRegsFrozen()
          ? MF.getRegInfo().getReservedRegs()
          : MF.getSubtarget().getRegisterInfo()->getReservedRegs(MF);
  for (MCRegister R :
       {ARM::R0, ARM::R1, ARM::R2, ARM::R3, ARM::R4, ARM::R5, ARM::R6, ARM::R7,
        ARM::R8, ARM::R9, ARM::R10, ARM::R11, ARM::R12, ARM::LR})
    if (Reserved.test(R))
      return false;
  return true;
}

static bool hasCleanupProtocol(const MachineFunction &MF) {
  return hasCleanupTarget(MF) && hasCleanupLayout(MF) &&
         hasCleanupEntryProtocol(MF) && hasCatchAndCleanupPads(MF) &&
         hasCleanupRegisters(MF);
}

static const Function *getCleanupCallee(const MachineInstr &MI) {
  for (const MachineOperand &MO : MI.operands())
    if (MO.isGlobal() && !MO.getOffset())
      return dyn_cast<Function>(MO.getGlobal());
  return nullptr;
}

static bool isCleanupDeclaration(const Function *Callee) {
  return Callee && Callee->getName() == "__cxa_end_cleanup" &&
         Callee->isDeclaration() && Callee->hasExternalLinkage() &&
         Callee->getCallingConv() == CallingConv::C && !Callee->isVarArg() &&
         Callee->getReturnType()->isVoidTy() && Callee->arg_empty();
}

bool llvm::isARMZeroizeCleanup(const MachineInstr &MI) {
  if ((MI.getOpcode() != ARM::BL && MI.getOpcode() != ARM::tBL) ||
      !MI.getParent()->succ_empty() || !hasCleanupProtocol(*MI.getMF()) ||
      !isCleanupDeclaration(getCleanupCallee(MI)))
    return false;
  return llvm::any_of(
             MI.operands(),
             [](const MachineOperand &MO) { return MO.isRegMask(); }) &&
         llvm::all_of(
             make_range(std::next(MI.getIterator()),
                        MI.getParent()->instr_end()),
             [](const MachineInstr &I) { return I.isMetaInstruction(); });
}

bool llvm::hasARMZeroizeCleanup(const MachineFunction &MF) {
  for (const MachineBasicBlock &MBB : MF)
    for (const MachineInstr &MI : MBB)
      if (isARMZeroizeCleanup(MI) && hasARMZeroizeCleanupFrame(MF) &&
          hasARMZeroizeCleanupInterface(MI))
        return true;
  return false;
}

static int getCleanupSaveSlot(const MachineFrameInfo &MFI,
                              const CalleeSavedInfo &CSI) {
  static constexpr MCPhysReg SavedGPRs[] = {ARM::R4,  ARM::R5,  ARM::R6,
                                            ARM::R7,  ARM::R8,  ARM::R9,
                                            ARM::R10, ARM::R11, ARM::LR};
  if (CSI.isSpilledToReg() || !is_contained(SavedGPRs, CSI.getReg()))
    return -1;
  int64_t Offset = MFI.getObjectOffset(CSI.getFrameIdx());
  if (Offset >= 0 || Offset % 4 ||
      Offset < -4 * int64_t(MFI.getCalleeSavedInfo().size()))
    return -1;
  return (-Offset / 4) - 1;
}

static bool hasBoundedCleanupFrame(const MachineFrameInfo &MFI) {
  // Snapshot size depends on saved GPRs, not the original allocation. Keep the
  // initial unrolled clearing profile small and its arithmetic representable.
  return MFI.getStackSize() <= 224 && MFI.getStackSize() % 8 == 0 &&
         MFI.getCalleeSavedInfo().size() <= 9 &&
         MFI.getStackSize() >= 4 * MFI.getCalleeSavedInfo().size();
}

bool llvm::hasARMZeroizeCleanupFrame(const MachineFunction &MF) {
  const auto &MFI = MF.getFrameInfo();
  if (!hasBoundedCleanupFrame(MFI))
    return false;
  BitVector Slots(MFI.getCalleeSavedInfo().size());
  bool HasR4 = false, HasLR = false;
  for (const CalleeSavedInfo &CSI : MFI.getCalleeSavedInfo()) {
    int Slot = getCleanupSaveSlot(MFI, CSI);
    if (Slot < 0 || Slots.test(Slot))
      return false;
    Slots.set(Slot);
    HasR4 |= CSI.getReg() == ARM::R4;
    HasLR |= CSI.getReg() == ARM::LR && Slot == 0;
  }
  return HasR4 && HasLR;
}

MCSymbol *llvm::getARMZeroizeSymbol(const MachineFunction &MF, StringRef Kind) {
  return MF.getContext().getOrCreateSymbol(Twine(".Larm_zeroize_") + Kind +
                                           "_" + Twine(MF.getFunctionNumber()));
}

static SmallVector<const MachineInstr *, 3>
reachingDefinitions(const MachineInstr &MI, MCRegister Reg, unsigned Count) {
  SmallVector<const MachineInstr *, 3> Definitions;
  const auto *TRI = MI.getMF()->getSubtarget().getRegisterInfo();
  for (auto I = MI.getIterator(); I != MI.getParent()->begin();) {
    --I;
    if (I->modifiesRegister(Reg, TRI)) {
      Definitions.push_back(&*I);
      if (Definitions.size() == Count)
        break;
    }
  }
  return Definitions;
}

static bool hasAddressRegisterOperands(const MachineInstr &MI, MCRegister Reg,
                                       unsigned Count) {
  for (unsigned I = 0; I != Count; ++I) {
    const MachineOperand &MO = MI.getOperand(I);
    if (!MO.isReg() || MO.getReg() != Reg || MO.getSubReg())
      return false;
  }
  return true;
}

static bool hasAddressHalf(const MachineInstr &MI, unsigned Opcode,
                           MCRegister Reg, MCSymbol *Symbol, unsigned Index) {
  if (MI.getOpcode() != Opcode || MI.getNumOperands() <= Index + 1 ||
      !hasAddressRegisterOperands(MI, Reg, Index))
    return false;
  const auto &MO = MI.getOperand(Index);
  return MO.isMCSymbol() && MO.getMCSymbol() == Symbol &&
         MO.getTargetFlags() == 0 && MI.getOperand(Index + 1).isImm();
}

static bool hasAddressAddition(const MachineInstr &MI, MCRegister Reg,
                               bool Thumb) {
  if (MI.getOpcode() != (Thumb ? ARM::tPICADD : ARM::PICADD) ||
      MI.getNumOperands() < (Thumb ? 3U : 5U))
    return false;
  return hasAddressRegisterOperands(MI, Reg, 2) && MI.getOperand(2).isImm() &&
         MI.getOperand(2).getImm() >= 0 &&
         !MI.getMF()->getSubtarget().getInstrInfo()->isPredicated(MI);
}

static bool hasFixedAddress(const MachineInstr &MI, MCRegister Reg,
                            StringRef Kind) {
  auto Defs = reachingDefinitions(MI, Reg, 3);
  if (Defs.size() != 3)
    return false;
  const auto &Add = *Defs[0], &High = *Defs[1], &Low = *Defs[2];
  bool Thumb = MI.getMF()->getSubtarget<ARMSubtarget>().isThumb();
  MCSymbol *Symbol = getARMZeroizeSymbol(*MI.getMF(), Kind);
  unsigned LowOpcode = Thumb ? ARM::t2MOVi16_ga_pcrel : ARM::MOVi16_ga_pcrel;
  unsigned HighOpcode = Thumb ? ARM::t2MOVTi16_ga_pcrel : ARM::MOVTi16_ga_pcrel;
  if (!hasAddressAddition(Add, Reg, Thumb) ||
      !hasAddressHalf(Low, LowOpcode, Reg, Symbol, 1) ||
      !hasAddressHalf(High, HighOpcode, Reg, Symbol, 2))
    return false;
  return Low.getOperand(2).getImm() == High.getOperand(3).getImm() &&
         Low.getOperand(2).getImm() == Add.getOperand(2).getImm();
}

static bool hasZeroSelector(const MachineInstr &MI) {
  auto Definitions = reachingDefinitions(MI, ARM::R2, 1);
  if (Definitions.empty())
    return false;
  const auto &Def = *Definitions.front();
  static constexpr unsigned ZeroOpcodes[] = {ARM::MOVi, ARM::t2MOVi,
                                             ARM::t2MOVi16, ARM::tMOVi8};
  if (!is_contained(ZeroOpcodes, Def.getOpcode()) ||
      Def.getMF()->getSubtarget().getInstrInfo()->isPredicated(Def))
    return false;
  const auto &Value = Def.getOperand(Def.getNumExplicitDefs());
  return hasAddressRegisterOperands(Def, ARM::R2, 1) && Value.isImm() &&
         Value.getImm() == 0;
}

bool llvm::hasARMZeroizeCleanupInterface(const MachineInstr &MI) {
  const auto *TRI = MI.getMF()->getSubtarget().getRegisterInfo();
  for (MCRegister R : {ARM::R1, ARM::R2, ARM::R4, ARM::R12, ARM::LR})
    if (!MI.readsRegister(R, TRI))
      return false;
  // Validate reaching definitions even without assertions or when replaying
  // serialized MIR. Implicit uses alone do not establish the required values.
  return hasFixedAddress(MI, ARM::R1, "continuation") &&
         hasFixedAddress(MI, ARM::R12, "carrier") && hasZeroSelector(MI);
}

namespace {
// Explicit machine emission keeps the complete private allocation bounded:
// no compiler-generated spills can appear after its final erasure.
class CleanupEmitter {
  MCStreamer &Out;
  MCContext &Ctx;
  ARMTargetStreamer &TS;
  MCSubtargetInfo STI;
  const MachineFunction &MF;
  SmallVector<MCRegister, 9> Saved = {ARM::R4,  ARM::R5,  ARM::R6,
                                      ARM::R7,  ARM::R8,  ARM::R9,
                                      ARM::R10, ARM::R11, ARM::LR};
  MCSymbol *Failure = nullptr;
  MCSymbol *Return = nullptr;

  void emit(const MCInst &MI) { Out.emitInstruction(MI, STI); }
  const MCExpr *ref(MCSymbol *Symbol) {
    return MCSymbolRefExpr::create(Symbol, Ctx);
  }
  MCSymbol *symbol(StringRef Kind) { return getARMZeroizeSymbol(MF, Kind); }
  void label(MCSymbol *Symbol) { Out.emitLabel(Symbol); }
  void mov(MCRegister Dst, MCRegister Src) {
    emit(MCInstBuilder(ARM::MOVr)
             .addReg(Dst)
             .addReg(Src)
             .addImm(ARMCC::AL)
             .addReg(0)
             .addReg(0));
  }
  void imm(MCRegister Dst, unsigned Value) {
    emit(MCInstBuilder(ARM::MOVi)
             .addReg(Dst)
             .addImm(Value)
             .addImm(ARMCC::AL)
             .addReg(0)
             .addReg(0));
  }
  void arithmetic(unsigned Opcode, MCRegister Dst, MCRegister Src, unsigned N) {
    emit(MCInstBuilder(Opcode)
             .addReg(Dst)
             .addReg(Src)
             .addImm(N)
             .addImm(ARMCC::AL)
             .addReg(0)
             .addReg(0));
  }
  void memory(unsigned Opcode, MCRegister Reg, MCRegister Base, unsigned N) {
    emit(MCInstBuilder(Opcode)
             .addReg(Reg)
             .addReg(Base)
             .addImm(N)
             .addImm(ARMCC::AL)
             .addReg(0));
  }
  void address(MCRegister Reg, MCSymbol *Symbol) {
    MCSymbol *Here = Ctx.createTempSymbol("cleanup_pc");
    const MCExpr *Delta = MCBinaryExpr::createSub(
        ref(Symbol),
        MCBinaryExpr::createAdd(ref(Here), MCConstantExpr::create(8, Ctx), Ctx),
        Ctx);
    emit(MCInstBuilder(ARM::MOVi16)
             .addReg(Reg)
             .addExpr(ARM::createLower16(Delta, Ctx))
             .addImm(ARMCC::AL)
             .addReg(0)
             .addReg(0));
    emit(MCInstBuilder(ARM::MOVTi16)
             .addReg(Reg)
             .addReg(Reg)
             .addExpr(ARM::createUpper16(Delta, Ctx))
             .addImm(ARMCC::AL)
             .addReg(0)
             .addReg(0));
    label(Here);
    emit(MCInstBuilder(ARM::ADDrr)
             .addReg(Reg)
             .addReg(ARM::PC)
             .addReg(Reg)
             .addImm(ARMCC::AL)
             .addReg(0)
             .addReg(0));
  }
  void compare(MCRegister Reg, unsigned Value) {
    emit(MCInstBuilder(ARM::CMPri)
             .addReg(Reg)
             .addImm(Value)
             .addImm(ARMCC::AL)
             .addReg(0));
  }
  void compareSymbol(MCRegister Reg, MCSymbol *Symbol) {
    address(ARM::R11, Symbol);
    emit(MCInstBuilder(ARM::CMPrr)
             .addReg(Reg)
             .addReg(ARM::R11)
             .addImm(ARMCC::AL)
             .addReg(0));
  }
  void branch(MCSymbol *Dest, ARMCC::CondCodes CC = ARMCC::AL) {
    emit(MCInstBuilder(ARM::Bcc).addExpr(ref(Dest)).addImm(CC).addReg(
        CC == ARMCC::AL ? 0 : ARM::CPSR));
  }
  void call(StringRef Name) {
    emit(MCInstBuilder(ARM::BL).addExpr(ref(Ctx.getOrCreateSymbol(Name))));
  }
  void get(unsigned Virtual, MCRegister Dst) {
    mov(ARM::R0, ARM::R6);
    imm(ARM::R1, 0);
    imm(ARM::R2, Virtual);
    imm(ARM::R3, 0);
    arithmetic(ARM::ADDri, ARM::R12, ARM::SP, 48);
    memory(ARM::STRi12, ARM::R12, ARM::SP, 0);
    call("_Unwind_VRS_Get");
    compare(ARM::R0, 0);
    branch(Failure, ARMCC::NE);
    memory(ARM::LDRi12, Dst, ARM::SP, 48);
  }
  void set(unsigned Virtual, MCRegister Src) {
    memory(ARM::STRi12, Src, ARM::SP, 48);
    mov(ARM::R0, ARM::R6);
    imm(ARM::R1, 0);
    imm(ARM::R2, Virtual);
    imm(ARM::R3, 0);
    arithmetic(ARM::ADDri, ARM::R12, ARM::SP, 48);
    memory(ARM::STRi12, ARM::R12, ARM::SP, 0);
    call("_Unwind_VRS_Set");
    compare(ARM::R0, 0);
    branch(Failure, ARMCC::NE);
  }
  void unwindFrame() {
    mov(ARM::R0, ARM::R5);
    mov(ARM::R1, ARM::R6);
    call("__gnu_unwind_frame");
    compare(ARM::R0, 0);
    branch(Failure, ARMCC::NE);
  }
  void start(MCSymbol *Name) {
    Out.emitCodeAlignment(Align(4), STI);
    Out.emitSymbolAttribute(Name, MCSA_ELF_TypeFunction);
    label(Name);
    TS.emitFnStart();
  }
  void end(MCSymbol *Name) {
    TS.emitFnEnd();
    MCSymbol *End = Ctx.createTempSymbol();
    label(End);
    Out.emitELFSize(Name, MCBinaryExpr::createSub(ref(End), ref(Name), Ctx));
  }
  void enter() {
    Failure = Ctx.createTempSymbol("cleanup_failure");
    Return = Ctx.createTempSymbol("cleanup_return");
    TS.emitRegSave(Saved, false);
    auto Push = MCInstBuilder(ARM::STMDB_UPD)
                    .addReg(ARM::SP)
                    .addReg(ARM::SP)
                    .addImm(ARMCC::AL)
                    .addReg(0);
    for (MCRegister R : Saved)
      Push.addReg(R);
    emit(Push);
    TS.emitPad(60);
    arithmetic(ARM::SUBri, ARM::SP, ARM::SP, 60);
    mov(ARM::R4, ARM::R0);
    mov(ARM::R5, ARM::R1);
    mov(ARM::R6, ARM::R2);
  }
  void leave() {
    branch(Return);
    label(Failure);
    imm(ARM::R0, 9); // _URC_FAILURE
    label(Return);
    arithmetic(ARM::ADDri, ARM::R12, ARM::SP, 60);
    auto Restore =
        MCInstBuilder(ARM::LDMIA).addReg(ARM::R12).addImm(ARMCC::AL).addReg(0);
    for (MCRegister R : Saved)
      Restore.addReg(R);
    emit(Restore);
    imm(ARM::R1, 0);
    for (unsigned Offset = 0; Offset != 96; Offset += 4)
      memory(ARM::STRi12, ARM::R1, ARM::SP, Offset);
    for (MCRegister R : {ARM::R1, ARM::R2, ARM::R3, ARM::R12})
      imm(R, 0);
    emit(MCInstBuilder(ARM::MSR)
             .addImm(8)
             .addReg(ARM::R1)
             .addImm(ARMCC::AL)
             .addReg(0));
    arithmetic(ARM::ADDri, ARM::SP, ARM::SP, 96);
    emit(MCInstBuilder(ARM::BX).addReg(ARM::LR));
  }
  void snapshot() {
    const auto &MFI = MF.getFrameInfo();
    // Map the original save slots onto a bounded private interval ending at
    // SP+44. The unwind recipe adjusts virtual SP before accessing those slots.
    for (const CalleeSavedInfo &CSI : MFI.getCalleeSavedInfo()) {
      MCRegister R = CSI.getReg();
      MCRegister Value = R == ARM::LR ? ARM::R7 : ARM::R9;
      if (R != ARM::LR && R != ARM::R4) {
        get(Ctx.getRegisterInfo()->getEncodingValue(R), ARM::R10);
        Value = ARM::R10;
      }
      memory(ARM::STRi12, Value, ARM::SP,
             44 + MFI.getObjectOffset(CSI.getFrameIdx()));
    }
    unsigned Size = MFI.getStackSize();
    arithmetic(Size > 44 ? ARM::SUBri : ARM::ADDri, ARM::R10, ARM::SP,
               Size > 44 ? Size - 44 : 44 - Size);
  }
  void phase() {
    MCSymbol *Name = symbol("personality");
    start(Name);
    enter();
    MCSymbol *Completed = Ctx.createTempSymbol("cleanup_completed");
    MCSymbol *Resume = Ctx.createTempSymbol("cleanup_resume");
    MCSymbol *Step = Ctx.createTempSymbol("cleanup_step");
    get(15, ARM::R7);
    get(13, ARM::R8);
    get(4, ARM::R9);
    arithmetic(ARM::BICri, ARM::R10, ARM::R7, 1);
    compareSymbol(ARM::R10, symbol("continuation"));
    branch(Completed, ARMCC::EQ);
    arithmetic(ARM::ANDri, ARM::R10, ARM::R4, 3);
    compare(ARM::R10, 2); // _US_UNWIND_FRAME_RESUME
    branch(Resume, ARMCC::EQ);
    mov(ARM::R0, ARM::R4);
    mov(ARM::R1, ARM::R5);
    mov(ARM::R2, ARM::R6);
    call("__gxx_personality_v0");
    compare(ARM::R0, 7); // _URC_INSTALL_CONTEXT
    branch(Return, ARMCC::NE);
    get(1, ARM::R10);
    compare(ARM::R10, 0);
    branch(Failure, ARMCC::LT); // Exception filters are not supported.
    // VRS_Get clobbers R0. Preserve the selected catching frame without
    // stepping it: phase 1 may already have identified it as the exception
    // barrier.
    imm(ARM::R0, 7); // _URC_INSTALL_CONTEXT
    branch(Return, ARMCC::NE);
    get(15, ARM::R7);
    get(13, ARM::R8);
    get(4, ARM::R9);
    set(2, ARM::R7);
    address(ARM::R7, symbol("install"));
    branch(Step);
    label(Completed);
    arithmetic(ARM::ADDri, ARM::R8, ARM::R9,
               MF.getFrameInfo().getStackSize() + 16);
    memory(ARM::LDRi12, ARM::R7, ARM::R9, 4);
    memory(ARM::LDRi12, ARM::R9, ARM::R9, 0);
    branch(Step);
    label(Resume);
    arithmetic(ARM::ADDri, ARM::R8, ARM::R9, 16);
    memory(ARM::LDRi12, ARM::R7, ARM::R9, 12);
    label(Step);
    snapshot();
    set(13, ARM::R10);
    unwindFrame();
    set(13, ARM::R8);
    imm(ARM::R0, 8); // _URC_CONTINUE_UNWIND
    leave();
    end(Name);
  }
  void helperPersonality() {
    MCSymbol *Name = symbol("helper_personality");
    start(Name);
    enter();
    MCSymbol *Step = Ctx.createTempSymbol("helper_step");
    get(15, ARM::R7);
    arithmetic(ARM::ANDri, ARM::R8, ARM::R4, 3);
    compare(ARM::R8, 1); // _US_UNWIND_FRAME_STARTING
    branch(Step, ARMCC::NE);
    arithmetic(ARM::BICri, ARM::R7, ARM::R7, 1);
    compareSymbol(ARM::R7, symbol("install"));
    branch(Step, ARMCC::NE);
    get(2, ARM::R7);
    set(15, ARM::R7);
    imm(ARM::R0, 7);
    branch(Return);
    label(Step);
    unwindFrame();
    imm(ARM::R0, 8);
    leave();
    end(Name);
  }
  void carrier() {
    MCSymbol *Name = symbol("carrier");
    start(Name);
    MCSymbol *Physical = Ctx.createTempSymbol("physical_carrier");
    branch(Physical);
    emit(MCInstBuilder(ARM::HINT).addImm(0).addImm(ARMCC::AL).addReg(0));
    label(symbol("install"));
    emit(MCInstBuilder(ARM::UDF).addImm(0));
    label(Physical);
    SmallVector<MCRegister, 1> LR = {ARM::LR};
    TS.emitRegSave(LR, false);
    TS.emitPad(12);
    arithmetic(ARM::SUBri, ARM::SP, ARM::SP, 16);
    for (auto [R, Offset] : {std::pair(ARM::R4, 0), std::pair(ARM::LR, 4),
                             std::pair(ARM::R2, 8), std::pair(ARM::R1, 12)})
      memory(ARM::STRi12, R, ARM::SP, Offset);
    mov(ARM::R4, ARM::SP);
    imm(ARM::R1, 0);
    imm(ARM::R12, 0);
    call("__cxa_end_cleanup");
    emit(MCInstBuilder(ARM::UDF).addImm(0));
    TS.emitPersonality(symbol("helper_personality"));
    TS.emitHandlerData();
    end(Name);
  }

public:
  CleanupEmitter(MCStreamer &Out, const MachineFunction &MF)
      : Out(Out), Ctx(Out.getContext()),
        TS(static_cast<ARMTargetStreamer &>(*Out.getTargetStreamer())),
        STI(MF.getSubtarget()), MF(MF) {
    if (STI.hasFeature(ARM::ModeThumb))
      STI.ToggleFeature(ARM::ModeThumb);
  }
  void run() {
    TS.emitCode32();
    carrier();
    phase();
    helperPersonality();
  }
};
} // namespace

void ARMAsmPrinter::emitZeroizeCleanupContinuation() {
  if (!hasARMZeroizeCleanup(*MF))
    return;
  // Return-PC lookup adjusts by one byte. Keep the preceding instruction in
  // this original function's EHABI range, even though neither executes.
  emitAlignment(Align(4));
  bool Thumb = AFI->isThumbFunction();
  EmitToStreamer(*OutStreamer, MCInstBuilder(Thumb ? ARM::t2HINT : ARM::HINT)
                                   .addImm(0)
                                   .addImm(ARMCC::AL)
                                   .addReg(0));
  OutStreamer->emitLabel(getARMZeroizeSymbol(*MF, "continuation"));
  EmitToStreamer(*OutStreamer,
                 MCInstBuilder(Thumb ? ARM::t2UDF : ARM::UDF).addImm(0));
}

void ARMAsmPrinter::emitZeroizeCleanupHelpers() {
  OutStreamer->switchSection(&CurrentFnSym->getSection());
  CleanupEmitter(*OutStreamer, *MF).run();
}
