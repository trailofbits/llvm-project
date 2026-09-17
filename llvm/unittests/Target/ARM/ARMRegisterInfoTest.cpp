//===----------------------------------------------------------------------===//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "MCTargetDesc/ARMMCTargetDesc.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/CodeGen/TargetRegisterInfo.h"
#include "llvm/CodeGen/TargetSubtargetInfo.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Module.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Target/TargetMachine.h"
#include "gtest/gtest.h"

using namespace llvm;

TEST(ARMRegisterInfoTest, SwiftArgumentAttributes) {
  LLVMInitializeARMTargetInfo();
  LLVMInitializeARMTarget();
  LLVMInitializeARMTargetMC();

  // Exercise APCS, AAPCS and AAPCS-VFP, including FastCC's APCS delegation.
  for (const char *TripleName :
       {"armv7-unknown-linux-gnueabi", "armv7-unknown-linux-gnueabihf",
        "armv7-apple-ios"}) {
    Triple TT(TripleName);
    std::string Error;
    const Target *T = TargetRegistry::lookupTarget(TT, Error);
    ASSERT_NE(T, nullptr) << Error;
    TargetOptions Options;
    std::unique_ptr<TargetMachine> TM(T->createTargetMachine(
        TT, "cortex-a9", "+neon", Options, std::nullopt));
    ASSERT_NE(TM, nullptr);

    for (CallingConv::ID CC : {CallingConv::C, CallingConv::Fast,
                               CallingConv::Swift, CallingConv::SwiftTail}) {
      for (bool HasSelf : {false, true}) {
        for (bool HasError : {false, true}) {
          SCOPED_TRACE(testing::Message()
                       << TripleName << " CC=" << CC << " self=" << HasSelf
                       << " error=" << HasError);
          LLVMContext Context;
          Module M("test", Context);
          M.setTargetTriple(TT);
          M.setDataLayout(TM->createDataLayout());
          Type *PtrTy = PointerType::getUnqual(Context);
          Function *F =
              Function::Create(FunctionType::get(Type::getVoidTy(Context),
                                                 {PtrTy, PtrTy}, false),
                               GlobalValue::ExternalLinkage, "f", M);
          F->setCallingConv(CC);
          if (HasSelf)
            F->addParamAttr(0, Attribute::SwiftSelf);
          if (HasError)
            F->addParamAttr(1, Attribute::SwiftError);

          MachineModuleInfo MMI(TM.get());
          MachineFunction &MF = MMI.getOrCreateMachineFunction(*F);
          const TargetRegisterInfo &TRI = *MF.getSubtarget().getRegisterInfo();
          bool IsSwift =
              CC == CallingConv::Swift || CC == CallingConv::SwiftTail;
          EXPECT_EQ(TRI.isArgumentRegister(MF, ARM::R10), IsSwift || HasSelf);
          EXPECT_EQ(TRI.isArgumentRegister(MF, ARM::R8), IsSwift || HasError);
          EXPECT_TRUE(TRI.isArgumentRegister(MF, ARM::R0));
          EXPECT_FALSE(TRI.isArgumentRegister(MF, ARM::R9));
        }
      }
    }
  }
}
