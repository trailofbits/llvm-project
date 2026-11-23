//===-- AArch64Zeroization.cpp - Exit state clearing
//------------------------===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "AArch64Zeroization.h"
#include "AArch64FrameLowering.h"
#include "AArch64InstrInfo.h"
#include "AArch64MachineFunctionInfo.h"
#include "AArch64Subtarget.h"
#include "Utils/AArch64BaseInfo.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/BinaryFormat/Dwarf.h"
#include "llvm/CodeGen/CFIInstBuilder.h"
#include "llvm/CodeGen/LivePhysRegs.h"
#include "llvm/CodeGen/LiveRegUnits.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/StackZeroization.h"
#include "llvm/IR/DiagnosticInfo.h"
#include "llvm/IR/EHPersonalities.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/LLVMContext.h"
#include "llvm/MC/MCContext.h"
#include "llvm/Target/TargetMachine.h"

using namespace llvm;

static bool hasSMEZeroizeProtocol(const AArch64FunctionInfo &AFI) {
  const SMEAttrs SME = AFI.getSMEFnAttrs();
  return AFI.hasStreamingModeChanges() || SME.hasStreamingInterfaceOrBody() ||
         SME.hasStreamingCompatibleInterface() || SME.hasZAState() ||
         SME.hasZT0State();
}

static bool hasOrdinaryZeroizeCallingConvention(const Function &F) {
  switch (F.getCallingConv()) {
  case CallingConv::C:
  case CallingConv::Fast:
  case CallingConv::AArch64_VectorCall:
  case CallingConv::AArch64_SVE_VectorCall:
    return true;
  default:
    return false;
  }
}

static bool mayInstrumentZeroizeExits(const Function &F) {
  Attribute Instrument = F.getFnAttribute("function-instrument");
  if (Instrument.isStringAttribute() &&
      Instrument.getValueAsString() == "xray-never")
    return false;
  // XRay runs after PEI. Its instruction-count decision is not final yet, and
  // an active exit sled calls a handler after the zeroization sequence.
  return (Instrument.isStringAttribute() &&
          Instrument.getValueAsString() == "xray-always") ||
         F.hasFnAttribute("xray-instruction-threshold");
}

bool llvm::hasAArch64ZeroizeUpperLaneABI(const MachineFunction &MF) {
  const auto &STI = MF.getSubtarget<AArch64Subtarget>();
  // In base AAPCS64 only D8-D15 are preserved. Writing the corresponding
  // upper V lanes also zeroes the bits above V in an SVE Z register.
  return STI.isTargetELF() &&
         MF.getFunction().getCallingConv() == CallingConv::C &&
         STI.hasFPARMv8() && !STI.hasSME() && !STI.isStreaming() &&
         !STI.isStreamingCompatible();
}

static bool hasAndroidShadowCallStack(const MachineFunction &MF) {
  const Function &F = MF.getFunction();
  const Triple &TT = MF.getTarget().getTargetTriple();
  const auto &STI = MF.getSubtarget<AArch64Subtarget>();
  return TT.isAndroid() && !TT.isAndroidVersionLT(29) &&
         F.getCallingConv() == CallingConv::C && F.hasZeroizeStack() &&
         F.hasFnAttribute(Attribute::ShadowCallStack) && !STI.hasSVE() &&
         STI.isXRegisterReserved(18);
}

static bool isTerminalCXXResume(const MachineInstr &MI) {
  if (MI.getOpcode() != AArch64::BL)
    return false;
  const auto &MF = *MI.getMF();
  const auto &F = MF.getFunction();
  if (!F.hasPersonalityFn() ||
      classifyEHPersonality(F.getPersonalityFn()) != EHPersonality::GNU_CXX)
    return false;

  if (!MI.getOperand(0).isGlobal() || MI.getOperand(0).getOffset() ||
      !MI.getParent()->succ_empty())
    return false;
  bool HasArgument = false;
  bool HasMask = false;
  for (const MachineOperand &MO : MI.operands()) {
    if (MO.isRegMask()) {
      HasMask = true;
    } else if (MO.isReg() && MO.isUse() && MO.readsReg() &&
               MO.getReg() == AArch64::X0) {
      HasArgument = true;
    }
  }
  if (!HasArgument || !HasMask)
    return false;
  const auto *Resume = dyn_cast<Function>(MI.getOperand(0).getGlobal());
  if (!Resume || !Resume->isDeclaration() || !Resume->hasExternalLinkage() ||
      Resume->getName() != "_Unwind_Resume" ||
      Resume->getCallingConv() != CallingConv::C || Resume->isVarArg() ||
      !Resume->getReturnType()->isVoidTy() || Resume->arg_size() != 1 ||
      !Resume->getArg(0)->getType()->isPointerTy())
    return false;
  return llvm::all_of(
      make_range(std::next(MI.getIterator()), MI.getParent()->instr_end()),
      [](const MachineInstr &I) { return I.isMetaInstruction(); });
}

bool llvm::isAArch64ZeroizeShadowResume(const MachineInstr &MI) {
  const MachineFunction &MF = *MI.getMF();
  const auto &AFI = *MF.getInfo<AArch64FunctionInfo>();
  return isTerminalCXXResume(MI) && hasAndroidShadowCallStack(MF) &&
         AFI.needsDwarfUnwindInfo(MF) &&
         AFI.needsShadowCallStackPrologueEpilogue(MF) &&
         llvm::none_of(MI.operands(), [](const MachineOperand &MO) {
           return MO.isRegMask() && MO.clobbersPhysReg(AArch64::X18);
         });
}

MCSymbol *llvm::getAArch64ZeroizeContinuation(const MachineFunction &MF) {
  return MF.getContext().getOrCreateSymbol(Twine(".Lzeroize_resume_") +
                                           Twine(MF.getFunctionNumber()));
}

bool llvm::hasAArch64ZeroizeCarrierInterface(const MachineInstr &MI) {
  const MachineFunction &MF = *MI.getMF();
  const auto *TRI = MF.getSubtarget().getRegisterInfo();
  for (MCRegister Reg : {AArch64::X1, AArch64::X21, AArch64::LR})
    if (!MI.readsRegister(Reg, TRI))
      return false;
  const MCSymbol *Continuation = getAArch64ZeroizeContinuation(MF);
  SmallVector<const MachineInstr *, 2> Definitions;
  for (auto I = MI.getIterator(); I != MI.getParent()->begin();) {
    --I;
    if (I->modifiesRegister(AArch64::X1, TRI)) {
      Definitions.push_back(&*I);
      if (Definitions.size() == 2)
        break;
    }
  }
  if (Definitions.size() != 2)
    return false;
  const MachineInstr &Add = *Definitions[0], &Page = *Definitions[1];
  return Add.getOpcode() == AArch64::ADDXri &&
         Add.getOperand(1).getReg() == AArch64::X1 &&
         Add.getOperand(2).isMCSymbol() &&
         Add.getOperand(2).getMCSymbol() == Continuation &&
         Add.getOperand(2).getTargetFlags() ==
             (AArch64II::MO_PAGEOFF | AArch64II::MO_NC) &&
         Add.getOperand(3).getImm() == 0 && Page.getOpcode() == AArch64::ADRP &&
         Page.getOperand(1).isMCSymbol() &&
         Page.getOperand(1).getMCSymbol() == Continuation &&
         Page.getOperand(1).getTargetFlags() == AArch64II::MO_PAGE;
}

static bool hasSupportedZeroizeABI(const MachineFunction &MF) {
  const Function &F = MF.getFunction();
  const auto &AFI = *MF.getInfo<AArch64FunctionInfo>();
  if (AFI.shouldSignReturnAddress(MF)) {
    // RETAA/RETAB authenticate LR with the restored entry SP. Neither uses a
    // scratch register. Other PAC protocols can insert work after clearing.
    const auto &STI = MF.getSubtarget<AArch64Subtarget>();
    if (!F.hasZeroizeStack() || F.getCallingConv() != CallingConv::C ||
        !STI.hasPAuth() || STI.hasSVE() || STI.hasSME() ||
        AFI.branchProtectionPAuthLR() || AFI.getArgumentStackToRestore() ||
        F.hasFnAttribute(Attribute::ShadowCallStack))
      return false;
  }
  return MF.getTarget().getTargetTriple().isOSBinFormatELF() &&
         hasOrdinaryZeroizeCallingConvention(F) &&
         !hasSMEZeroizeProtocol(AFI) && !AFI.hasSwiftAsyncContext() &&
         (!F.hasFnAttribute(Attribute::ShadowCallStack) ||
          hasAndroidShadowCallStack(MF)) &&
         !mayInstrumentZeroizeExits(F);
}

bool llvm::isAArch64ZeroizeUnwindResume(const MachineInstr &MI) {
  if (!MI.isCall())
    return false;
  for (const MachineOperand &MO : MI.operands()) {
    StringRef Name;
    if (MO.isGlobal())
      Name = MO.getGlobal()->getName();
    else if (MO.isSymbol())
      Name = MO.getSymbolName();
    if (Name == "_Unwind_Resume" || Name == "__cxa_end_cleanup")
      return true;
  }
  return false;
}

static bool isUnsupportedZeroizeExit(const MachineInstr &MI) {
  if (MI.isEHScopeReturn())
    return true;
  if (isAArch64ZeroizeUnwindResume(MI))
    return !isAArch64ZeroizeShadowResume(MI) &&
           !isAArch64ZeroizeCarrierResume(MI);
  return MI.isReturn() && (MI.getOpcode() != AArch64::RET_ReallyLR ||
                           !MI.getParent()->succ_empty());
}

static bool hasSupportedZeroizeExits(const MachineFunction &MF) {
  if (!hasSupportedZeroizeABI(MF))
    return false;
  for (const MachineBasicBlock &MBB : MF)
    for (const MachineInstr &MI : MBB)
      if (isUnsupportedZeroizeExit(MI))
        return false;
  return true;
}

static void
computeZeroizeLiveUnits(LiveRegUnits &Live, const MachineBasicBlock &MBB,
                        MachineBasicBlock::const_iterator InsertPt) {
  Live.addLiveOuts(MBB);
  for (auto I = MBB.end(); I != InsertPt;) {
    --I;
    if (!I->isDebugInstr())
      Live.stepBackward(*I);
  }
}

bool AArch64FrameLowering::isOrdinaryZeroizeReturn(
    const MachineInstr &MI) const {
  return MI.getOpcode() == AArch64::RET_ReallyLR ||
         (MI.getOpcode() == AArch64::RET &&
          MI.getOperand(0).getReg() == AArch64::LR);
}

bool AArch64FrameLowering::supportsZeroizeFlags(
    const MachineFunction &MF) const {
  return hasSupportedZeroizeExits(MF);
}

bool AArch64FrameLowering::prepareZeroizeFlags(
    MachineBasicBlock &MBB, MachineBasicBlock::iterator InsertPt,
    BitVector &ScratchRegs) const {
  const auto &TRI = *MBB.getParent()->getSubtarget().getRegisterInfo();
  LiveRegUnits Live(TRI);
  computeZeroizeLiveUnits(Live, MBB, InsertPt);
  if (Live.available(AArch64::NZCV))
    return true;
  const Function &F = MBB.getParent()->getFunction();
  F.getContext().diagnose(DiagnosticInfoUnsupported{
      F, "flags clearing requires dead NZCV at the exit"});
  return false;
}

void AArch64FrameLowering::emitZeroizeFlags(
    MachineBasicBlock &MBB, MachineBasicBlock::iterator InsertPt,
    const BitVector &ScratchRegs, BitVector &ClearedRegs) const {
  const auto &TII = *MBB.getParent()->getSubtarget().getInstrInfo();
  auto MSR =
      BuildMI(MBB, InsertPt, InsertPt->getDebugLoc(), TII.get(AArch64::MSR))
          .addImm(AArch64SysReg::NZCV)
          .addReg(AArch64::XZR)
          .addReg(AArch64::NZCV, RegState::ImplicitDefine)
          .addReg(AArch64::SP, RegState::Implicit);
  assert(MSR->hasUnmodeledSideEffects() && "MSR must order memory effects");
  // Preserve its position after register clearing and stack release even when
  // late scheduling rearranges otherwise independent instructions.
  for (unsigned Reg : ClearedRegs.set_bits())
    if (Reg != AArch64::NZCV && Reg != AArch64::SP)
      MSR.addReg(Reg, RegState::Implicit);
  ClearedRegs.set(AArch64::NZCV);
}

bool llvm::shouldVerifyAArch64ZeroizedRegisters(const MachineFunction &MF) {
  const Function &F = MF.getFunction();
  Attribute Regs = F.getFnAttribute("zero-call-used-regs");
  return Regs.isStringAttribute() && Regs.getValueAsString() == "all" &&
         !F.hasFnAttribute(Attribute::Naked) && hasSupportedZeroizeABI(MF) &&
         !MF.getSubtarget<AArch64Subtarget>().isSVEorStreamingSVEAvailable();
}

static bool hasOrdinaryZeroizeStorage(const MachineFunction &MF) {
  const Function &F = MF.getFunction();
  const auto &AFI = *MF.getInfo<AArch64FunctionInfo>();
  return !F.isVarArg() && !F.hasFnAttribute(Attribute::SafeStack) &&
         !F.hasFnAttribute(Attribute::SanitizeHWAddress) &&
         !F.hasFnAttribute(Attribute::SanitizeMemTag) &&
         !MF.shouldSplitStack() && !AFI.hasSplitSVEObjects();
}

static bool hasFixedZeroizeLayout(const MachineFunction &MF, Align StackAlign) {
  const auto &MFI = MF.getFrameInfo();
  const auto &TRI = *MF.getSubtarget().getRegisterInfo();
  return !MFI.hasVarSizedObjects() && !MFI.hasOpaqueSPAdjustment() &&
         MFI.getMaxAlign() <= StackAlign && !TRI.hasStackRealignment(MF) &&
         MFI.getSavePoints().empty() && MFI.getRestorePoints().empty();
}

static bool hasOrdinaryZeroizeFrameProtocol(const MachineFunction &MF) {
  const auto &MFI = MF.getFrameInfo();
  const auto &AFI = *MF.getInfo<AArch64FunctionInfo>();
  return !MF.hasEHFunclets() && !MFI.hasStackMap() && !MFI.hasPatchPoint() &&
         !AFI.getArgumentStackToRestore();
}

static bool hasUntrackedZeroizeStorage(const MachineFunction &MF) {
  for (const MachineBasicBlock &MBB : MF)
    for (const MachineInstr &MI : MBB)
      // These pseudos allocate stack storage during MC lowering, outside the
      // frame extent known to PEI, even with XRay entry/exit hooks disabled.
      if (MI.getOpcode() == TargetOpcode::PATCHABLE_EVENT_CALL ||
          MI.getOpcode() == TargetOpcode::PATCHABLE_TYPED_EVENT_CALL)
        return true;
  return false;
}

static bool hasCarrierResumeProtocol(const MachineFunction &MF) {
  const Function &F = MF.getFunction();
  const auto &STI = MF.getSubtarget<AArch64Subtarget>();
  const auto &AFI = *MF.getInfo<AArch64FunctionInfo>();
  return F.getCallingConv() == CallingConv::C && !STI.isXRegisterReserved(1) &&
         !STI.isXRegisterReserved(21) && !STI.hasSVE() && !STI.hasSME() &&
         !AFI.shouldSignReturnAddress(MF) &&
         !F.hasFnAttribute(Attribute::ShadowCallStack) && !MF.hasBBSections() &&
         AFI.needsDwarfUnwindInfo(MF);
}

bool llvm::isAArch64ZeroizeCarrierResume(const MachineInstr &MI) {
  const MachineFunction &MF = *MI.getMF();
  Align StackAlign = MF.getSubtarget().getFrameLowering()->getStackAlign();
  return isTerminalCXXResume(MI) && MF.getFunction().hasZeroizeStack() &&
         hasSupportedZeroizeABI(MF) && hasOrdinaryZeroizeStorage(MF) &&
         hasFixedZeroizeLayout(MF, StackAlign) &&
         hasOrdinaryZeroizeFrameProtocol(MF) &&
         !hasUntrackedZeroizeStorage(MF) && hasCarrierResumeProtocol(MF);
}

bool AArch64FrameLowering::supportsZeroizeStack(
    const MachineFunction &MF) const {
  // These layouts need runtime extents, storage outside the ordinary frame,
  // or a different unwind protocol. Leave their ordinary epilogues intact.
  return hasSupportedZeroizeExits(MF) && hasOrdinaryZeroizeStorage(MF) &&
         hasFixedZeroizeLayout(MF, getStackAlign()) &&
         hasOrdinaryZeroizeFrameProtocol(MF) && !hasUntrackedZeroizeStorage(MF);
}

namespace {

static bool isValidZeroizeExtent(StackOffset Size) {
  return Size.getFixed() >= 0 && Size.getScalable() >= 0 &&
         Size.getFixed() <= INT32_MAX && Size.getScalable() <= INT32_MAX &&
         Size.getFixed() % 16 == 0 && Size.getScalable() % 16 == 0;
}

static SmallVector<MCRegister, 2> findZeroizeScratch(const MachineFunction &MF,
                                                     const LiveRegUnits &Live,
                                                     unsigned Count) {
  SmallVector<MCRegister, 2> Regs;
  for (MCRegister Reg : {AArch64::X9, AArch64::X10, AArch64::X11, AArch64::X12,
                         AArch64::X13, AArch64::X14, AArch64::X15}) {
    if (MF.getRegInfo().isReserved(Reg) || !Live.available(Reg))
      continue;
    Regs.push_back(Reg);
    if (Regs.size() == Count)
      break;
  }
  return Regs;
}

class AArch64StackClearEmitter {
  MachineBasicBlock &MBB;
  MachineBasicBlock::iterator InsertPt;
  MachineFunction &MF;
  const MachineFrameInfo &MFI;
  const AArch64FrameLowering &TFI;
  const AArch64InstrInfo &TII;
  const AArch64RegisterInfo &TRI;
  DebugLoc DL;
  StackOffset Size;
  MCRegister Ptr;
  MCRegister End;
  bool ShadowCallStack;
  bool UnwindResume;

  bool fail(StringRef Message) const {
    const Function &F = MF.getFunction();
    F.getContext().diagnose(DiagnosticInfoUnsupported{F, Message});
    return false;
  }

  static unsigned restoreOpcode(MCRegister Reg) {
    if (AArch64::GPR64RegClass.contains(Reg))
      return AArch64::LDRXui;
    if (AArch64::FPR64RegClass.contains(Reg))
      return AArch64::LDRDui;
    if (AArch64::FPR128RegClass.contains(Reg))
      return AArch64::LDRQui;
    if (AArch64::ZPRRegClass.contains(Reg))
      return AArch64::LDR_ZXI;
    if (AArch64::PPRRegClass.contains(Reg))
      return AArch64::LDR_PXI;
    return 0;
  }

  bool needsClearing(int FI) const {
    return !MFI.isDeadObjectIndex(FI) &&
           MFI.getStackID(FI) != TargetStackID::NoAlloc &&
           !(MFI.isFixedObjectIndex(FI) && MFI.getObjectOffset(FI) >= 0);
  }

  bool validateFixedObjects() const {
    SmallVector<StackZeroizeRange> Objects;
    for (int FI = MFI.getObjectIndexBegin(); FI < MFI.getObjectIndexEnd(); ++FI)
      if (needsClearing(FI))
        Objects.push_back({TargetStackID::Default,
                           TFI.getFrameIndexReferenceFromSP(MF, FI).getFixed(),
                           uint64_t(MFI.getObjectSize(FI)),
                           MFI.getObjectAlign(FI)});
    StackZeroizeRange Owned{TargetStackID::Default, -Size.getFixed(),
                            uint64_t(Size.getFixed()), Align(16)};
    auto Extent = computeStackZeroizeExtent({Owned}, Objects);
    if (!Extent)
      return fail(toString(Extent.takeError()));
    return true;
  }

  bool validateScalableObjects() const {
    for (int FI = MFI.getObjectIndexBegin(); FI < MFI.getObjectIndexEnd();
         ++FI) {
      if (!needsClearing(FI))
        continue;
      StackOffset Offset = TFI.getFrameIndexReferenceFromSP(MF, FI);
      StackOffset Bottom = Size + Offset;
      StackOffset ObjectSize =
          MFI.hasScalableStackID(FI)
              ? StackOffset::getScalable(MFI.getObjectSize(FI))
              : StackOffset::getFixed(MFI.getObjectSize(FI));
      StackOffset Top = Offset + ObjectSize;
      // Component-wise containment proves coverage at every supported VL.
      if (Bottom.getFixed() < 0 || Bottom.getScalable() < 0 ||
          Top.getFixed() > 0 || Top.getScalable() > 0)
        return fail("stack clearing cannot cover an object outside the owned "
                    "AArch64 frame");
    }
    return true;
  }

  bool validateCalleeSaves() const {
    for (const CalleeSavedInfo &CSI : MFI.getCalleeSavedInfo())
      if (CSI.isSpilledToReg() || !restoreOpcode(CSI.getReg()))
        return fail("stack clearing encountered an unsupported AArch64 "
                    "callee-save slot");
    return true;
  }

  bool validate() const {
    if (!isValidZeroizeExtent(Size))
      return fail("stack clearing requires an aligned AArch64 frame extent");
    // For the supported prologue, locals and callee saves form a contiguous
    // allocation. No red zone, dynamic realignment or separate stack is used.
    const auto &AFI = *MF.getInfo<AArch64FunctionInfo>();
    if (AFI.getLocalStackSize() + AFI.getCalleeSavedStackSize() !=
        MFI.getStackSize())
      return fail("stack clearing cannot establish AArch64 frame ownership");
    if (!(Size.getScalable() ? validateScalableObjects()
                             : validateFixedObjects()))
      return false;
    return validateCalleeSaves();
  }

  bool selectScratch(BitVector &ScratchRegs, bool Loop) {
    LiveRegUnits Live(TRI);
    computeZeroizeLiveUnits(Live, MBB, InsertPt);
    if (Loop && !Live.available(AArch64::NZCV))
      return fail("stack clearing requires dead NZCV at the exit");
    unsigned Count = Loop ? 2 : 1;
    SmallVector<MCRegister, 2> Regs = findZeroizeScratch(MF, Live, Count);
    if (Regs.size() != Count)
      return fail("stack clearing needs free caller-saved AArch64 registers");
    Ptr = Regs[0];
    ScratchRegs.set(Ptr);
    if (Loop) {
      End = Regs[1];
      ScratchRegs.set(End);
    }
    return true;
  }

  void restoreShadowReturnAddress() {
    CFIInstBuilder CFI(MBB, InsertPt, MachineInstr::FrameDestroy);
    if (UnwindResume) {
      // BL overwrites LR. Leave the real frame and its shadow entry in place
      // until the unwinder steps over them. The ordinary save is erased below.
      static const char Rule[] = {dwarf::DW_CFA_expression, 30, 2,
                                  static_cast<char>(dwarf::DW_OP_breg18),
                                  0x78}; // [X18 - 8]
      CFI.buildEscape(StringRef(Rule, sizeof(Rule)));
      return;
    }
    TFI.emitShadowCallStackPop(MBB, InsertPt, DL);
    CFI.buildRestore(AArch64::X18);
    CFI.buildRestore(AArch64::LR);
  }

  void restore() {
    unsigned CFI =
        MF.addFrameInst(createDefCFA(TRI, AArch64::SP, AArch64::SP, Size));
    BuildMI(MBB, InsertPt, DL, TII.get(TargetOpcode::CFI_INSTRUCTION))
        .addCFIIndex(CFI)
        .setMIFlag(MachineInstr::FrameDestroy);
    for (const CalleeSavedInfo &CSI : MFI.getCalleeSavedInfo()) {
      if (CSI.getReg() == AArch64::LR && ShadowCallStack) {
        restoreShadowReturnAddress();
        continue;
      }
      int FI = CSI.getFrameIdx();
      StackOffset Offset = Size + TFI.getFrameIndexReferenceFromSP(MF, FI);
      emitFrameOffset(MBB, InsertPt, DL, Ptr, AArch64::SP, Offset, &TII);
      TypeSize LoadSize = MFI.hasScalableStackID(FI)
                              ? TypeSize::getScalable(MFI.getObjectSize(FI))
                              : TypeSize::getFixed(MFI.getObjectSize(FI));
      BuildMI(MBB, InsertPt, DL, TII.get(restoreOpcode(CSI.getReg())),
              CSI.getReg())
          .addReg(Ptr)
          .addImm(0)
          .setMIFlag(MachineInstr::FrameDestroy)
          .addMemOperand(MF.getMachineMemOperand(
              MachinePointerInfo::getFixedStack(MF, FI),
              MachineMemOperand::MOLoad, LoadSize, MFI.getObjectAlign(FI)));
      MCRegister Reg = CSI.getReg();
      // The unwinder consumes the restored caller context through the CFI
      // rule, even when a clearing loop separates the load from the call.
      if (UnwindResume)
        InsertPt->addOperand(MF, MachineOperand::CreateReg(Reg, /*isDef=*/false,
                                                           /*isImp=*/true));
      if (!MFI.hasScalableStackID(FI) || TRI.regNeedsCFI(Reg, Reg))
        CFIInstBuilder(MBB, InsertPt, MachineInstr::FrameDestroy)
            .buildRestore(Reg);
    }
  }

  void store(MachineBasicBlock &Block, MachineBasicBlock::iterator I,
             unsigned Offset) {
    BuildMI(Block, I, DL, TII.get(AArch64::STPXi))
        .addReg(AArch64::XZR)
        .addReg(AArch64::XZR)
        .addReg(Ptr)
        .addImm(Offset / 8)
        .addMemOperand(MF.getMachineMemOperand(
            MachinePointerInfo(),
            MachineMemOperand::MOStore | MachineMemOperand::MOVolatile, 16,
            Align(16)));
  }

  MachineBasicBlock *emitLoop() {
    auto *Body = MF.CreateMachineBasicBlock(MBB.getBasicBlock());
    auto *Tail = MF.CreateMachineBasicBlock(MBB.getBasicBlock());
    MF.insert(std::next(MBB.getIterator()), Body);
    MF.insert(std::next(Body->getIterator()), Tail);
    Tail->splice(Tail->end(), &MBB, InsertPt, MBB.end());
    Tail->transferSuccessorsAndUpdatePHIs(&MBB);
    MBB.addSuccessor(Body);
    Body->addSuccessor(Body);
    Body->addSuccessor(Tail);
    store(*Body, Body->end(), 0);
    emitFrameOffset(*Body, Body->end(), DL, Ptr, Ptr, StackOffset::getFixed(16),
                    &TII);
    BuildMI(*Body, Body->end(), DL, TII.get(AArch64::SUBSXrs), AArch64::XZR)
        .addReg(Ptr)
        .addReg(End)
        .addImm(0);
    BuildMI(*Body, Body->end(), DL, TII.get(AArch64::Bcc))
        .addImm(AArch64CC::NE)
        .addMBB(Body);
    InsertPt = Tail->begin();
    return Tail;
  }

  void finish(MachineBasicBlock &Tail, bool Loop) {
    if (!UnwindResume) {
      emitFrameOffset(Tail, InsertPt, DL, AArch64::SP, Ptr, {}, &TII,
                      MachineInstr::FrameDestroy);
      CFIInstBuilder(Tail, InsertPt, MachineInstr::FrameDestroy)
          .buildDefCFA(AArch64::SP, 0);
    }
    if (isAArch64ZeroizeCarrierResume(*InsertPt)) {
      // This constant is independent of the selected cleanup and protected
      // data. Keep it and the restored caller context live through clearing.
      MCSymbol *Continuation = getAArch64ZeroizeContinuation(MF);
      BuildMI(Tail, InsertPt, DL, TII.get(AArch64::ADRP), AArch64::X1)
          .addSym(Continuation, AArch64II::MO_PAGE);
      BuildMI(Tail, InsertPt, DL, TII.get(AArch64::ADDXri), AArch64::X1)
          .addReg(AArch64::X1)
          .addSym(Continuation, AArch64II::MO_PAGEOFF | AArch64II::MO_NC)
          .addImm(0);
      for (MCRegister Reg : {AArch64::X1, AArch64::X21, AArch64::LR})
        if (!InsertPt->readsRegister(Reg, &TRI))
          InsertPt->addOperand(MF, MachineOperand::CreateReg(Reg, false, true));
    }
    if (Loop) {
      MachineBasicBlock *Body = Tail.getSinglePredecessor();
      assert(Body && "Expected a single clearing-loop predecessor");
      fullyRecomputeLiveIns({&Tail, Body});
    }
  }

public:
  AArch64StackClearEmitter(MachineBasicBlock &MBB,
                           MachineBasicBlock::iterator InsertPt,
                           const AArch64FrameLowering &TFI)
      : MBB(MBB), InsertPt(InsertPt), MF(*MBB.getParent()),
        MFI(MF.getFrameInfo()), TFI(TFI),
        TII(*MF.getSubtarget<AArch64Subtarget>().getInstrInfo()),
        TRI(*MF.getSubtarget<AArch64Subtarget>().getRegisterInfo()),
        DL(InsertPt->getDebugLoc()),
        Size(StackOffset::getFixed(MFI.getStackSize()) +
             TFI.getSVEStackSize(MF)),
        ShadowCallStack(MF.getInfo<AArch64FunctionInfo>()
                            ->needsShadowCallStackPrologueEpilogue(MF)),
        UnwindResume(isAArch64ZeroizeUnwindResume(*InsertPt)) {}

  void emit(BitVector &ScratchRegs) {
    if (!Size || !validate())
      return;
    bool Loop = Size.getScalable() || Size.getFixed() > 64;
    if (!selectScratch(ScratchRegs, Loop))
      return;
    restore();
    emitFrameOffset(MBB, InsertPt, DL, Ptr, AArch64::SP, {}, &TII);
    MachineBasicBlock *Tail = &MBB;
    if (Loop) {
      emitFrameOffset(MBB, InsertPt, DL, End, AArch64::SP, Size, &TII);
      Tail = emitLoop();
    } else {
      for (unsigned Offset = 0; Offset < Size.getFixed(); Offset += 16)
        store(MBB, InsertPt, Offset);
      if (!UnwindResume)
        emitFrameOffset(MBB, InsertPt, DL, Ptr, Ptr, Size, &TII);
    }
    finish(*Tail, Loop);
  }
};

} // end anonymous namespace

void AArch64FrameLowering::emitZeroizeStack(
    MachineBasicBlock &MBB, MachineBasicBlock::iterator InsertPt,
    BitVector &ScratchRegs) const {
  MachineInstr &Exit = *InsertPt;
  AArch64StackClearEmitter(MBB, InsertPt, *this).emit(ScratchRegs);
  const MachineFunction &MF = *MBB.getParent();
  if (MF.getInfo<AArch64FunctionInfo>()->shouldSignReturnAddress(MF) &&
      !shouldSignReturnAddressEverywhere(MF)) {
    // Our teardown replaces the ordinary frame epilogue. A clearing loop can
    // move the return into a new block. Authenticate in that block.
    MF.getSubtarget<AArch64Subtarget>()
        .getInstrInfo()
        ->createPauthEpilogueInstr(*Exit.getParent(), Exit.getDebugLoc());
  }
}
