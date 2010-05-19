# Tcl package index file, version 1.0

package ifneeded Itcl 3.3 [format {
  # this logic avoids catching an inappropriate load request
  if {[lsearch -exact [info loaded] {{} Itcl}] >= 0} {
    load "" Itcl
  } else {
    load %s Itcl
  }
} [list [file join $dir libitcl3.3[info sharedlibext]]]]
