// RUN: mlir-opt %s | FileCheck %s --check-prefix=MLIR
// RUN: mlir-translate -mlir-to-llvmir %s | FileCheck %s --check-prefix=LLVM
// RUN: mlir-translate -mlir-to-llvmir %s | mlir-translate -import-llvm | FileCheck \
// RUN:   %s --check-prefix=MLIR

// MLIR-LABEL: llvm.func @used()
// MLIR-SAME: attributes {zeroize_stack = "used"}
// LLVM: declare void @used() #[[USED:[0-9]+]]
llvm.func @used() attributes {zeroize_stack = "used"}

// MLIR-LABEL: llvm.func @sensitive()
// MLIR-SAME: attributes {zeroize_stack = "sensitive"}
// LLVM: declare void @sensitive() #[[SENSITIVE:[0-9]+]]
llvm.func @sensitive() attributes {zeroize_stack = "sensitive"}

// Empty and unrecognized values are permitted by LLVM IR and must survive translation.
// MLIR-LABEL: llvm.func @default_mode()
// MLIR-SAME: attributes {zeroize_stack = ""}
// LLVM: declare void @default_mode() #[[DEFAULT:[0-9]+]]
llvm.func @default_mode() attributes {zeroize_stack = ""}

// MLIR-LABEL: llvm.func @unknown_mode()
// MLIR-SAME: attributes {zeroize_stack = "future-mode"}
// LLVM: declare void @unknown_mode() #[[UNKNOWN:[0-9]+]]
llvm.func @unknown_mode() attributes {zeroize_stack = "future-mode"}

// LLVM-DAG: attributes #[[USED]] = { "zeroize-stack"="used" }
// LLVM-DAG: attributes #[[SENSITIVE]] = { "zeroize-stack"="sensitive" }
// LLVM-DAG: attributes #[[DEFAULT]] = { "zeroize-stack" }
// LLVM-DAG: attributes #[[UNKNOWN]] = { "zeroize-stack"="future-mode" }
