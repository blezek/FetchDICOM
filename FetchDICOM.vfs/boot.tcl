proc tclInit {} {
  rename tclInit {}

  global auto_path tcl_library tcl_libPath
  global tcl_version tcl_rcFileName
  
  set noe [info nameofexecutable]

  set tcl_library [file join $noe lib tcl$tcl_version]
  set tcl_libPath [list $tcl_library [file join $noe lib]]

  # get rid of a build residue
  unset -nocomplain ::tclDefaultLibrary

# the following code only gets executed once on startup
  if {[info exists tcl_rcFileName]} {
    load {} pwb
    load {} vfs

    # lookup and emulate "source" of lib/vfs/{vfs*.tcl,mk4vfs.tcl}
    # must use raw MetaKit calls because VFS is not yet in place

    set d [mk::select exe.dirs parent 0 name lib]
    set d [mk::select exe.dirs parent $d name vfs]
    
    foreach x {vfsUtils vfslib mk4vfs} {
      set n [mk::select exe.dirs!$d.files name $x.tcl]
      set s [mk::get exe.dirs!$d.files!$n contents]
      catch {set s [zlib decompress $s]}
      uplevel #0 $s
    }

    # use on-the-fly decompression, if mk4vfs understands that
    set mk4vfs::zstreamed 1

    # mount the executable, i.e. make all runtime files available
    vfs::filesystem mount $noe [list ::vfs::mk4::handler exe]

    # alter path to find encodings
    librarypath [info library]

    # fix system encoding, if it wasn't properly set up (200207.004 bug)
    if {[encoding system] eq "identity"} {
      switch $::tcl_platform(platform) {
        windows		{ encoding system cp1252 }
        macintosh	{ encoding system macRoman }
        default		{ encoding system iso8859-1 }
      }
    }

    # now remount the executable with the correct encoding
    vfs::filesystem unmount $noe
    set noe [info nameofexecutable]
    set tcl_library [file join $noe lib tcl$tcl_version]
    set tcl_libPath [list $tcl_library [file join $noe lib]]
    vfs::filesystem mount $noe [list ::vfs::mk4::handler exe]
  }
  
  # load config settings file if present
  namespace eval ::vfs { variable tclkit_version 1 }
  catch { uplevel #0 [list source [file join $noe config.tcl]] }

  uplevel #0 [list source [file join $tcl_library init.tcl]]
  
# reset auto_path, so that init.tcl's search outside of tclkit is cancelled
  set auto_path $tcl_libPath
}
