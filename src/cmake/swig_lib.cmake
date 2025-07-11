# SPDX-License-Identifier: BSD-3-Clause
# Copyright (c) 2021-2025, The OpenROAD Authors

# Sets up swig for a .i file and encode .tcl files
# Arguments
#   NAME <library>: the generated library name
#   I_FILE <file>: the .i file input to swig
#   NAMESPACE <name>: the namespace prefix in TCL
#   SWIG_INCLUDES <dir>* : optional list of include dirs for swig
#   SCRIPTS <file>* : tcl files to encode
#
# The intention is that this will create a library target with the
# generated code in it.  Additional c++ source will be added to the
# target with target_sources() afterwards.

function(swig_lib)

  # Parse args
  set(options "")
  set(oneValueArgs I_FILE NAME NAMESPACE LANGUAGE RUNTIME_HEADER)
  set(multiValueArgs SWIG_INCLUDES SCRIPTS)
  
  cmake_parse_arguments(
      ARG  # prefix on the parsed args
      "${options}"
      "${oneValueArgs}"
      "${multiValueArgs}"
      ${ARGN}
  )

  # Validate args
  if (DEFINED ARG_UNPARSED_ARGUMENTS)
     message(FATAL_ERROR "Unknown argument(s) to swig_lib: ${ARG_UNPARSED_ARGUMENTS}")
  endif()

  if (DEFINED ARG_KEYWORDS_MISSING_VALUES)
     message(FATAL_ERROR "Missing value for argument(s) to swig_lib: ${ARG_KEYWORDS_MISSING_VALUES}")
  endif()

  foreach(arg I_FILE NAME NAMESPACE)
    if (NOT DEFINED ARG_${arg})
       message(FATAL_ERROR "${arg} argument must be provided to swig_lib")
    endif()
  endforeach()

  # Default to tcl if unspecified
  if (NOT DEFINED ARG_LANGUAGE)
    set(ARG_LANGUAGE tcl)
  endif()

  set_source_files_properties(${ARG_I_FILE} PROPERTIES CPLUSPLUS ON)

  if (DEFINED ARG_SWIG_INCLUDES)
    set_property(SOURCE ${ARG_I_FILE}
                 PROPERTY INCLUDE_DIRECTORIES ${ARG_SWIG_INCLUDES})
  endif()

  if (${ARG_LANGUAGE} STREQUAL "tcl")
    set(LANGUAGE_OPTIONS -namespace -prefix ${ARG_NAMESPACE})
  endif()

  # Setup swig of I_FILE.
  set_property(SOURCE ${ARG_I_FILE}
    PROPERTY COMPILE_OPTIONS ${LANGUAGE_OPTIONS}
      -Werror
      -w317,325,378,401,402,451,467,472,503,509)

  set_property(SOURCE ${ARG_I_FILE}
               PROPERTY SWIG_MODULE_NAME ${ARG_NAME})
  set_property(SOURCE ${ARG_I_FILE}
               PROPERTY USE_SWIG_DEPENDENCIES TRUE)
  set_property(SOURCE ${ARG_I_FILE}
               PROPERTY USE_TARGET_INCLUDE_DIRECTORIES true)

  swig_add_library(${ARG_NAME}
    LANGUAGE ${ARG_LANGUAGE}
    TYPE     STATIC
    SOURCES  ${ARG_I_FILE}
  )

  # Disable problematic compiler warnings on generated files.
  # At this point only the swig generated sources are present.
  get_target_property(GEN_SRCS ${ARG_NAME} SOURCES)

  foreach(GEN_SRC ${GEN_SRCS})
    set_source_files_properties(${GEN_SRC}
      PROPERTIES
        COMPILE_OPTIONS "-Wno-cast-qual;-Wno-missing-braces;-Wno-missing-field-initializers"
    )
  endforeach()

  # These includes are always needed.
  target_include_directories(${ARG_NAME}
    PRIVATE
      ${OPENROAD_HOME}/include
  )

  if (${ARG_LANGUAGE} STREQUAL tcl)
    target_include_directories(${ARG_NAME}
      PRIVATE
        ${TCL_INCLUDE_PATH}
    )
  elseif (${ARG_LANGUAGE} STREQUAL python)
    target_include_directories(${ARG_NAME}
      PRIVATE
        ${Python3_INCLUDE_DIRS}
    )
    if (SWIG_VERSION VERSION_GREATER_EQUAL "4.1.0")
      set_property(TARGET ${ARG_NAME} PROPERTY SWIG_COMPILE_OPTIONS -flatstaticmethod)
    endif()

    swig_link_libraries(${ARG_NAME}
      PUBLIC
        Python3::Python
    )
  endif()
  
  if (DEFINED ARG_RUNTIME_HEADER)
    add_custom_command(
      OUTPUT ${ARG_RUNTIME_HEADER}
      COMMAND ${SWIG_EXECUTABLE} -${ARG_LANGUAGE} -external-runtime ${ARG_RUNTIME_HEADER}
      WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    )
    add_custom_target(${ARG_NAME}_RUNTIME_HEADER
      DEPENDS ${ARG_RUNTIME_HEADER}
    )
    add_dependencies(${ARG_NAME}
      ${ARG_NAME}_RUNTIME_HEADER
    )
    target_include_directories(${ARG_NAME}
      PRIVATE
        ${CMAKE_CURRENT_BINARY_DIR}
    )
  endif()

  # Generate the encoded of the script files.
  if (DEFINED ARG_SCRIPTS)
    set(LANG_INIT ${CMAKE_CURRENT_BINARY_DIR}/${ARG_NAME}-${ARG_LANGUAGE}InitVar.cc)

    add_custom_command(OUTPUT ${LANG_INIT}
      COMMAND ${CMAKE_SOURCE_DIR}/etc/file_to_string.py
      --inputs ${ARG_SCRIPTS}
      --output ${LANG_INIT}
      --varname ${ARG_NAME}_${ARG_LANGUAGE}_inits
      --namespace ${ARG_NAMESPACE}
      WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
      DEPENDS ${ARG_SCRIPTS}
    )

    target_sources(${ARG_NAME}
      PRIVATE
        ${LANG_INIT}
    )
  endif()
endfunction()
