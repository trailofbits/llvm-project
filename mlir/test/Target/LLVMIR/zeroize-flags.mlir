// RUN: mlir-opt %s | FileCheck %s --check-prefix=MLIR
// RUN: mlir-translate -mlir-to-llvmir %s | FileCheck %s --check-prefix=LLVM
// RUN: mlir-translate -mlir-to-llvmir %s | mlir-translate -import-llvm | FileCheck \
// RUN:   %s --check-prefix=MLIR

// MLIR-LABEL: llvm.func @clear_flags()
// MLIR-SAME: attributes {zeroize_flags}
// LLVM: declare void @clear_flags() #[[FLAGS:[0-9]+]]
llvm.func @clear_flags() attributes {zeroize_flags}

// MLIR-LABEL: llvm.func @clear_all()
// MLIR-SAME: attributes {zero_call_used_regs = "all", zeroize_flags, zeroize_stack = "used"}
// LLVM: declare void @clear_all() #[[ALL:[0-9]+]]
llvm.func @clear_all() attributes {
  zero_call_used_regs = "all", zeroize_flags, zeroize_stack = "used"
}

// MLIR-LABEL: llvm.func @plain()
// MLIR-NOT: zeroize_flags
// LLVM: declare void @plain(){{$}}
llvm.func @plain()

// LLVM-DAG: attributes #[[FLAGS]] = { "zeroize-flags" }
// LLVM-DAG: #[[ALL]] = { "zero-call-used-regs"="all" "zeroize-flags" "zeroize-stack"="used" }
