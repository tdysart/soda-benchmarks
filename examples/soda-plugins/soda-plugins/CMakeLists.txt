set(SODAPLUGIN_LIBS
        MLIRSODAP
        MLIRSODAPDataflow
        MLIRSODAPDataflowTransforms
        MLIRSODAPAffineToDataflow
        MLIRSODAPDataflowToLLVM
        MLIRLinalgToESPRuntime
        )

add_llvm_library(SODAPlugin
        # BUILDTREE_ONLY is only for testing purposes
        MODULE BUILDTREE_ONLY
        soda-plugins.cpp

        DEPENDS
        ${SODAPLUGIN_LIBS}
        PLUGIN_TOOL
        mlir-opt
        )

# Only this project's archives go into the plugin: every MLIR and LLVM symbol
# they need is left undefined and bound to mlir-opt's exported copy at load
# time. Linking the targets instead would drag their transitive MLIR/LLVM
# static libraries in as a second copy, and the static cl::opts of LLVMCore
# (reached through the LLVM dialect) then register twice and abort the load:
# "Option 'use-dereferenceable-at-point-semantics' registered more than once".
# The files, not the targets, so that no link interface comes along; whole
# archive, so that no member is dropped for being unreferenced at link time.
#
# The one exception is MLIRTargetLLVMIRImport, which mlir-opt does not carry:
# ConvertDataflowToLLVM needs its TypeFromLLVMIRTranslator. As a plain archive
# the linker takes only the member that defines it (TypeFromLLVM.cpp.o, no
# cl::opts), and that member's own references still bind to mlir-opt.
set(SODAPLUGIN_ARCHIVES)
foreach(lib ${SODAPLUGIN_LIBS})
  if(APPLE)
    # ld64 has no --whole-archive; -force_load is its per-archive equivalent.
    list(APPEND SODAPLUGIN_ARCHIVES -Wl,-force_load,$<TARGET_FILE:${lib}>)
  else()
    list(APPEND SODAPLUGIN_ARCHIVES $<TARGET_FILE:${lib}>)
  endif()
endforeach()
if(APPLE)
  target_link_libraries(SODAPlugin PRIVATE
          ${SODAPLUGIN_ARCHIVES}
          $<TARGET_FILE:MLIRTargetLLVMIRImport>)
else()
  target_link_libraries(SODAPlugin PRIVATE
          -Wl,--whole-archive ${SODAPLUGIN_ARCHIVES} -Wl,--no-whole-archive
          $<TARGET_FILE:MLIRTargetLLVMIRImport>)
endif()

target_include_directories(
        SODAPlugin
        PRIVATE
        "${SODAP_BINARY_DIR}/include"
)
