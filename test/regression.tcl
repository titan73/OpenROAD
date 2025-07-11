# Copied from OpenSTA/test/regression.tcl
# Copyright (c) 2021, Parallax Software, Inc.
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

#  regression -help | [-threads threads] [-valgrind] [-report_stats] test1 [test2...]

# This is a generic regression test script used to compare application
# output to a known good "ok" file.
#
# Use the "regression" command to run the regressions.
#
#  regression -help | [-valgrind] test1 [test2...]
#
# where test is "all" or the name of a test group defined in regression_vars.tcl
# Wildcards can be used in test names if the name is enclosed in ""s to suppress
# shell globbing. For example,
#
#  regression "init_floorplan*"
#
# will run all tests with names that begin with "init_floorplan".
# Each test name is printed before it runs. Once it finishes pass,
# fail, *NO OK FILE* or *SEG FAULT* is printed after the test name.
#
# The results of each test are in the file test/results/<test>.log
# The diffs for all tests are in test/results/diffs.
# A list of failed tests is in test/results/failures.
# To save a log file as the correct output use the save_ok command.
#
#  save_ok failures | test1 [test2...]
#
# This copies test/results/test.log to test/test.ok
# Using the test name 'failures' copies the ok files for all failed tests.
# This is a quick way to update the failing test ok files after examining
# the differences.
#
# You should NOT need to modify this script.
# Customization unique to an application is in "regression_vars.tcl".
# In this case the application is OpenROAD, so nothing should need to be changed
# in "regression_vars.tcl".
#
# Customize the scripts "regresssion" and "save_ok" to source this file
# and a file that defines the test scripts, "regresion_tests.tcl".
# Each test is a tcl command file.

set openroad_test_dir [file join $openroad_dir "test"]

source [file join $openroad_test_dir "regression_vars.tcl"]
source [file join $openroad_test_dir "flow_metrics.tcl"]

proc regression_main { } {
  global argv
  exit [regression_body $argv]
}

proc regression_body { cmd_argv } {
  setup
  parse_args $cmd_argv
  run_tests
  show_summary
  return [found_errors]
}

proc setup { } {
  global result_dir diff_file failure_file errors
  global use_valgrind valgrind_shared_lib_failure

  set use_valgrind 0

  if { !([file exists $result_dir] && [file isdirectory $result_dir]) } {
    file mkdir $result_dir
  }
  file delete $diff_file
  file delete $failure_file

  set errors(error) 0
  set errors(memory) 0
  set errors(leak) 0
  set errors(fail) 0
  set errors(no_cmd) 0
  set errors(no_ok) 0
  set valgrind_shared_lib_failure 0
}

proc parse_args { cmd_argv } {
  global app_options tests test_groups cmd_paths
  global use_valgrind
  global result_dir tests

  while { $cmd_argv != {} } {
    set arg [lindex $cmd_argv 0]
    if { $arg == "help" || $arg == "-help" } {
      puts {Usage: regression [-help] [-threads threads] [-valgrind] tests...}
      puts "  -threads max|integer - number of threads to use"
      puts "  -valgrind - run valgrind (linux memory checker)"
      puts "  Wildcarding for test names is supported (enclose in \"'s)"
      puts "  Tests are: all, fast, med, slow, or a test group or test name"
      puts ""
      puts "  If 'limit coredumpsize unlimited' corefiles are saved in $result_dir/test.core"
      exit
    } elseif { $arg == "-threads" } {
      set threads [lindex $cmd_argv 1]
      if { !([string is integer $threads] || $threads == "max") } {
        puts "Error: -threads arg $threads is not an integer or max."
        exit 0
      }
      lappend app_options "-threads"
      lappend app_options $threads
      set cmd_argv [lrange $cmd_argv 2 end]
    } elseif { $arg == "-valgrind" } {
      set use_valgrind 1
      set cmd_argv [lrange $cmd_argv 1 end]
    } else {
      break
    }
  }
  if { $cmd_argv == {} } {
    # Default is to run all tests.
    set tests [group_tests all]
  } else {
    set tests [expand_tests $cmd_argv]
  }
}

proc expand_tests { tests_arg } {
  global test_groups

  set tests {}
  foreach arg $tests_arg {
    if { [info exists test_groups($arg)] } {
      set tests [concat $tests $test_groups($arg)]
    } elseif {
      [string first "*" $arg] != -1
      || [string first "?" $arg] != -1
    } {
      # Find wildcard matches.
      foreach test [group_tests "all"] {
        if { [string match $arg $test] } {
          lappend tests $test
        }
      }
    } elseif { [lsearch [group_tests "all"] $arg] != -1 } {
      lappend tests $arg
    } else {
      puts "Error: test $arg not found."
    }
  }
  return $tests
}

proc run_tests { } {
  global tests errors app_path

  foreach test $tests {
    run_test $test
  }
  # Macos debug info generated by valgrind.
  file delete -force "$app_path.dSYM"
}

proc run_test { test } {
  global test_langs

  set langs $test_langs($test)
  if { [llength $langs] == 0 } {
    puts "$test *NO CMD FILE*"
    incr errors(no_cmd)
  }
  foreach lang $langs {
    run_test_lang $test $lang
  }
}

proc run_test_lang { test lang } {
  global result_dir diff_file errors diff_options

  set cmd_file [test_cmd_file $test $lang]
  if { [file exists $cmd_file] } {
    set ok_file [test_ok_file $test]
    set log_file [test_log_file $test $lang]
    foreach file [glob -nocomplain [file join $result_dir $test-$lang.*]] {
      file delete -force $file
    }
    puts -nonewline "$test ($lang)"
    flush stdout
    set test_errors [run_test_app $test $cmd_file $log_file $lang]
    if { [lindex $test_errors 0] == "ERROR" } {
      puts " *ERROR* [lrange $test_errors 1 end]"
      append_failure $test
      incr errors(error)

      # For some reason seg faults aren't echoed in the log - add them.
      if { [file exists $log_file] } {
        set log_ch [open $log_file "a"]
        puts $log_ch "$test_errors"
        close $log_ch
      }

      # Report partial log diff anyway.
      if { [file exists $ok_file] } {
        # tclint-disable-next-line command-args
        catch [concat exec diff $diff_options $ok_file $log_file \
          >> $diff_file]
      }
    } else {
      set error_msg ""
      if { [lsearch $test_errors "MEMORY"] != -1 } {
        append error_msg " *MEMORY*"
        append_failure $test
        incr errors(memory)
      }
      if { [lsearch $test_errors "LEAK"] != -1 } {
        append error_msg " *LEAK*"
        append_failure $test
        incr errors(leak)
      }

      switch [test_pass_criteria $test] {
        compare_logfile {
          if { [file exists $ok_file] } {
            # Filter dos '/r's from log file.
            set tmp_file [file join $result_dir $test.tmp]
            exec tr -d "\r" < $log_file > $tmp_file
            file rename -force $tmp_file $log_file
            # tclint-disable-next-line command-args
            if [catch [concat exec diff $diff_options $ok_file $log_file \
              >> $diff_file]] {
              puts " *FAIL*$error_msg"
              append_failure $test
              incr errors(fail)
            } else {
              puts " pass$error_msg"
            }
          } else {
            puts " *NO OK FILE*$error_msg"
            append_failure $test
            incr errors(no_ok)
          }
        }
        pass_fail {
          set error_msg [find_log_pass_fail $log_file]
          if { $error_msg != "pass" } {
            puts " *FAIL* $error_msg"
            append_failure $test
            incr errors(fail)
          } else {
            puts " pass"
          }
        }
        check_metrics {
          set error_msg [check_test_metrics $test $lang]
          if { $error_msg != "pass" } {
            puts " *FAIL* $error_msg"
            append_failure $test
            incr errors(fail)
          } else {
            puts " pass"
          }
        }
      }
    }
  } else {
    puts "$test ($lang) *NO CMD FILE*"
    incr errors(no_cmd)
  }
}

proc find_log_pass_fail { log_file } {
  if { [file exists $log_file] } {
    set stream [open $log_file r]
    set last_line ""
    while { [gets $stream line] >= 0 } {
      set last_line $line
    }
    close $stream
    if { [string match "pass*" $last_line] } {
      return "pass"
    } else {
      return $last_line
    }
  }
  return "fail - reason not found"
}

proc append_failure { test } {
  global failure_file
  set fail_ch [open $failure_file "a"]
  puts $fail_ch $test
  close $fail_ch
}

# Return error.
proc run_test_app { test cmd_file log_file lang } {
  global app_path errorCode use_valgrind
  if { $use_valgrind } {
    return [run_test_valgrind $test $cmd_file $log_file $lang]
  } else {
    return [run_test_plain $test $cmd_file $log_file $lang]
  }
}

proc run_test_plain { test cmd_file log_file lang } {
  global app_path app_options result_dir errorCode

  if { ![file exists $app_path] } {
    return "ERROR $app_path not found."
  } elseif { ![file executable $app_path] } {
    return "ERROR $app_path is not executable."
  } else {
    set save_dir [pwd]
    cd [file dirname $cmd_file]
    # tclint-disable command-args
    if {
      [catch [concat exec $app_path $app_options \
        [lang_flag $lang] \
        -metrics [test_metrics_result_file $test $lang] \
        [file tail $cmd_file] >& $log_file]]
    } {
      # tclint-enable command-args
      cd $save_dir
      set signal [lindex $errorCode 2]
      set error [lindex $errorCode 3]
      # Errors strings are not consistent across platforms but signal
      # names are.
      if { $signal == "SIGSEGV" } {
        # Save corefiles to regression results directory.
        set pid [lindex $errorCode 1]
        set sys_corefile [test_sys_core_file $test $pid]
        if { [file exists $sys_corefile] } {
          file copy $sys_corefile [test_core_file $test $lang]
        }
      }
      cleanse_logfile $test $log_file
      return "ERROR $error"
    }
    cd $save_dir
    cleanse_logfile $test $log_file
    return ""
  }
}

proc run_test_valgrind { test cmd_file log_file lang } {
  global app_path app_options valgrind_options result_dir errorCode

  set vg_cmd_file [test_valgrind_cmd_file $test $lang]
  set vg_stream [open $vg_cmd_file "w"]
  puts $vg_stream "cd [file dirname $cmd_file]"
  puts $vg_stream "source [file tail $cmd_file]"
  close $vg_stream

  set cmd [concat exec valgrind $valgrind_options \
    $app_path [lang_flag $lang] $app_options \
    $vg_cmd_file >& $log_file]
  set error_msg ""
  if { [catch { $cmd }] } {
    set error_msg "ERROR [lindex $errorCode 3]"
  }
  file delete $vg_cmd_file
  cleanse_logfile $test $log_file
  lappend error_msg [cleanse_valgrind_logfile $test $log_file $lang]
  return $error_msg
}

# Error messages can be found in "valgrind/memcheck/mc_errcontext.c".
#
# "Conditional jump or move depends on uninitialised value(s)"
# "%s contains unaddressable byte(s)"
# "%s contains uninitialised or unaddressable byte(s)"
# "Use of uninitialised value of size %d"
# "Invalid read of size %d"
# "Syscall param %s contains uninitialised or unaddressable byte(s)"
# "Unaddressable byte(s) found during client check request"
# "Uninitialised or unaddressable byte(s) found during client check request"
# "Invalid free() / delete / delete[]"
# "Mismatched free() / delete / delete []"
set parts {
    "This is the first part"
    "This is the second part"
    "This is the final part"
}
set parts {
  "(depends on uninitialised value)"
  "(contains unaddressable)"
  "(contains uninitialised)"
  "(Use of uninitialised value)"
  "(Invalid read)"
  "(Unaddressable byte)"
  "(Uninitialised or unaddressable)"
  "(Invalid free)"
  "(Mismatched free)"
}
set valgrind_mem_regexp [join $parts "|"]


# "%d bytes in %d blocks are definitely lost in loss record %d of %d"
# "%d bytes in %d blocks are possibly lost in loss record %d of %d"
#set valgrind_leak_regexp "blocks are (possibly|definitely) lost"
set valgrind_leak_regexp "blocks are definitely lost"

# Valgrind fails on executables using shared libraries.
set valgrind_shared_lib_failure_regexp "No malloc'd blocks -- no leaks are possible"

# Scan the log file to separate valgrind notifications and check for
# valgrind errors.
proc cleanse_valgrind_logfile { test log_file lang } {
  global valgrind_mem_regexp valgrind_leak_regexp
  global valgrind_shared_lib_failure_regexp
  global valgrind_shared_lib_failure

  set tmp_file [test_tmp_file $test]
  set valgrind_log_file [test_valgrind_file $test $lang]
  file copy -force $log_file $tmp_file
  set tmp [open $tmp_file "r"]
  set log [open $log_file "w"]
  set valgrind [open $valgrind_log_file "w"]
  set leaks 0
  set mem_errors 0
  gets $tmp line
  while { ![eof $tmp] } {
    if { [regexp "^==" $line] } {
      puts $valgrind $line
      if { [regexp $valgrind_leak_regexp $line] } {
        set leaks 1
      }
      if { [regexp $valgrind_mem_regexp $line] } {
        set mem_errors 1
      }
      if { [regexp $valgrind_shared_lib_failure_regexp $line] } {
        set valgrind_shared_lib_failure 1
      }
    } elseif { [regexp {^--[0-9]+} $line] } {
      # Valgrind notification line.
    } else {
      puts $log $line
    }
    gets $tmp line
  }
  close $log
  close $tmp
  close $valgrind
  file delete $tmp_file

  set errors {}
  if { $mem_errors } {
    lappend errors "MEMORY"
  }
  if { $leaks } {
    lappend errors "LEAK"
  }
  return $errors
}

################################################################

proc show_summary { } {
  global errors tests diff_file result_dir valgrind_shared_lib_failure
  global app_path app

  puts "------------------------------------------------------"
  set test_count [llength $tests]
  if { [found_errors] } {
    if { $errors(error) != 0 } {
      puts "Errored $errors(error)/$test_count"
    }
    if { $errors(fail) != 0 } {
      puts "Failed $errors(fail)/$test_count"
    }
    if { $errors(leak) != 0 } {
      puts "Memory leaks in $errors(leak)/$test_count"
    }
    if { $errors(memory) != 0 } {
      puts "Memory corruption in $errors(memory)/$test_count"
    }
    if { $errors(no_ok) != 0 } {
      puts "No ok file for $errors(no_ok)/$test_count"
    }
    if { $errors(no_cmd) != 0 } {
      puts "No cmd tcl file for $errors(no_cmd)/$test_count"
    }
    if { $errors(fail) != 0 } {
      puts "See $diff_file for differences"
    }
  } else {
    puts "Passed $test_count"
  }
  if { $valgrind_shared_lib_failure } {
    puts "WARNING: valgrind failed because the executable is not statically linked."
  }
  puts "See $result_dir for log files"
}

proc found_errors { } {
  global errors

  return [expr $errors(error) != 0 || $errors(fail) != 0 \
    || $errors(no_cmd) != 0 || $errors(no_ok) != 0 \
    || $errors(memory) != 0 || $errors(leak) != 0]
}

################################################################

proc save_ok_main { } {
  global argv
  if { $argv == "help" || $argv == "-help" } {
    puts {Usage: save_ok [failures] test1 [test2]...}
  } else {
    if { $argv == "failures" } {
      set tests [failed_tests]
    } else {
      set tests $argv
    }
    foreach test $tests {
      if { [lsearch [group_tests "all"] $test] == -1 } {
        puts "Error: test $test not found."
      } else {
        save_ok $test
      }
    }
  }
}

proc failed_tests { } {
  global failure_file

  set failures {}
  if { [file exists $failure_file] } {
    set fail_ch [open $failure_file "r"]
    while { ![eof $fail_ch] } {
      set test [gets $fail_ch]
      if { $test != "" } {
        lappend failures $test
      }
    }
    close $fail_ch
  }
  return $failures
}

proc save_ok { test } {
  set ok_file [test_ok_file $test]
  set log_file [test_log_file $test [result_lang $test]]
  if { ![file exists $log_file] } {
    puts "Error: log file $log_file not found."
  } else {
    file copy -force $log_file $ok_file
  }
}

################################################################

proc save_defok_main { } {
  global argv
  if { $argv == "help" || $argv == "-help" } {
    puts {Usage: save_defok [failures] test1 [test2]...}
  } else {
    if { $argv == "failures" } {
      set tests [failed_tests]
    } else {
      set tests $argv
    }
    foreach test $tests {
      if { [lsearch [group_tests "all"] $test] == -1 } {
        puts "Error: test $test not found."
      } else {
        save_defok $test
      }
    }
  }
}

proc save_defok { test } {
  set defok_file [test_defok_file $test]
  set def_file [test_def_result_file $test [result_lang $test]]
  if { [file exists $def_file] } {
    file copy -force $def_file $defok_file
  }
}

################################################################

proc result_lang { test } {
  global test_langs

  if { [lsearch $test_langs($test) tcl] != -1 } {
    return tcl
  }
  return [lindex $test_langs($test) 0]
}

proc test_cmd_dir { test } {
  global cmd_dirs

  if { [info exists cmd_dirs($test)] } {
    return $cmd_dirs($test)
  } else {
    return ""
  }
}

proc test_cmd_file { test lang } {
  return [file join [test_cmd_dir $test] "$test.$lang"]
}

proc test_ok_file { test } {
  global test_dir
  return [file join $test_dir "$test.ok"]
}

proc test_defok_file { test } {
  global test_dir
  return [file join $test_dir "$test.defok"]
}

proc test_log_file { test lang } {
  global result_dir
  return [file join $result_dir "$test-$lang.log"]
}

proc test_def_result_file { test lang } {
  global result_dir
  return [file join $result_dir "$test-$lang.def"]
}

proc lang_flag { lang } {
  if { $lang == "py" } {
    return "-python"
  }
  return ""
}

proc test_tmp_file { test } {
  global result_dir
  return [file join $result_dir $test.tmp]
}

proc test_valgrind_cmd_file { test lang } {
  global result_dir
  return [file join $result_dir $test-$lang.vg_cmd]
}

proc test_valgrind_file { test lang } {
  global result_dir
  return [file join $result_dir $test-$lang.valgrind]
}

proc test_core_file { test lang } {
  global result_dir
  return [file join $result_dir $test-$lang.core]
}

proc test_sys_core_file { test pid } {
  global cmd_dirs

  # macos
  # return [file join "/cores" "core.$pid"]

  # Suse
  return [file join [test_cmd_dir $test] "core"]
}

proc test_pass_criteria { test } {
  global test_pass_criteria

  return $test_pass_criteria($test)
}

################################################################

# Local Variables:
# mode:tcl
# End:
