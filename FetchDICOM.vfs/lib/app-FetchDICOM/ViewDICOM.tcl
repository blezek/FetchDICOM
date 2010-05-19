package provide ViewDICOM 1.0

package require Tk
package require mkWidgets
package require BWidget
package require struct

proc InitViews {} {
  global Views
  if { ![info exists Views(Count)] } {
    set Views(Count) 0
    set Views(Windows) ""
  }
}

proc Close { w } {
  global Views
  destroy $w
  # Free the cache if any
  foreach p $Views($w,PhotoCache) {
    if { $p != "" } {
      image delete $p
    }
  }
  # unset any and all variables
  foreach key [array names Views -glob $w*] {
    unset Views($key)
  }
}

proc View { w } {
  global Views

  Log "Starting View"
  if { $Views($w,CurrentStudyInstanceUID) == "" } { return }
  set StudyInstanceUID $Views($w,CurrentStudyInstanceUID)
    
  set RowNumber [$Views($w,SeriesList) selection get]
  if { $RowNumber == "" } { return }
  incr RowNumber -1
  set SeriesInstanceUID [lindex [lindex $Views($w,$StudyInstanceUID,SeriesSort) $RowNumber] end]

  Log "Seleced $SeriesInstanceUID in browser"
  Log "Current $Views($w,CurrentStudyInstanceUID)"

  if { $Views($w,CurrentSeriesInstanceUID) != $SeriesInstanceUID } {
    Log "Clearing cache"
    $Views($w,Scale) configure -state disabled
    set Dir $Views($w,$SeriesInstanceUID,Directory)
    if { ![info exists Views($w,$SeriesInstanceUID,Files)] } {
      # Fill in the files
      set Files [lsort -dictionary [glob -nocomplain -- [file join $Dir *]]]
      set Count 0
      set NumberOfFiles [llength $Files]
      foreach File $Files {
        set Views($w,Status) "Processing files..."
        incr Count
        set Views($w,Progress) [expr 100 *  ( $Count / double($NumberOfFiles) )]
        array unset Tags
        set Answer [GetDicomTags $File [list {StudyID 1} {SeriesNumber 1} {StudyDescription ""}] \
                    [list StudyInstanceUID PatientsName PatientID StudyID StudyDate StudyDescription SeriesInstanceUID SeriesNumber SeriesDescription InstanceNumber]]
        if { $Answer == "" } { continue }
        array set Tags $Answer
        lappend Views($w,$SeriesInstanceUID,Files) [list $Tags(InstanceNumber) $File]
      }
    }
    
    set Files $Views($w,$SeriesInstanceUID,Files)
    # Sort and put back
    set Files [lsort -integer -index 0 $Files]
    set Views($w,$SeriesInstanceUID,Files) $Files
    set Views($w,CurrentView) $Files

    # Clear out the cache
    foreach p $Views($w,PhotoCache) {
      if { $p != "" } {
        image delete $p
      }
    }
    # Cache images
    set Views($w,PhotoCache) ""
    foreach f $Files {
      lappend Views($w,PhotoCache) ""
    }
    
    set Views($w,CurrentSeriesInstanceUID) $SeriesInstanceUID
    $Views($w,Scale) configure -from 0 -to [expr [llength $Files] - 1] -state normal
  }
  Log "Leaving View"
  Display $w
  BGCache $w
}


proc LoadCache { w i } {
  global Views env
  # load and create the photo
  set FileInfo [lindex $Views($w,CurrentView) $i]

  set Filename [file join $env(HOME) .viewdicom Temp.$i$w.ppm]
  file mkdir [file dir $Filename]
  
  Log "Starting LoadCache"

  # Log "File exists: [file exists [DCMTK dcm2pnm]]"
  # Log "File executable: [file executable [DCMTK dcm2pnm]]"
  # Log "File dcmdump [DCMTK dcmdump] executable: [file executable [DCMTK dcmdump]]"

  # set Command "[DCMTK dcmdump] [lindex $FileInfo 1]"

  # Log "Test dcmdump \nw/command $Command:"
  # Log "[ExecuteInBackground $Command]"
  # Log "Test dcm2pnm [ExecuteInBackground [DCMTK dcm2pnm]]"
  # set Command "[DCMTK dcm2pnm] [lindex $FileInfo 1]"
  # Log "Test dcm2pnm:"
  # Log "[ExecuteInBackground $Command]"

  set Command "[DCMTK dcm2pnm] --write-raw-pnm --min-max-window-n [lindex $FileInfo 1] $Filename"
  # Just exec this one, prevents race conditions
  # set Result [ExecuteInBackground $Command]
  set Result [catch "exec $Command" Data]
  Log "Result: $Result"
  set p [image create photo -file $Filename]
  file delete $Filename
  
  Log "Loading $p with $FileInfo"
  set Views($w,PhotoCache) [lreplace $Views($w,PhotoCache) $i $i $p]
  return $p
}

proc BGCache { w {idx 0} } {
  global Views

  # Do a bg load of the cache
  if { ! $Views($w,LoadInBackground) } { return }
  set idx [lsearch $Views($w,PhotoCache) ""]
  if { $idx == -1 } { 
    set Views($w,Progress) 0
    set Views($w,Status) ""
    return
  }
  LoadCache $w $idx
  update
  set NumberOfImages [llength $Views($w,PhotoCache)]
  set Views($w,Status) "Caching image $idx / $NumberOfImages"
  set Views($w,Progress) [expr 100 *  ( $idx / double($NumberOfImages ) )]
  after idle "BGCache $w"
  Log "BGCache $w $idx"
}
  

proc Display { w {idx 0} } {
  global Views

  if { $Views($w,CurrentSeriesInstanceUID) == "" } { return }
  # See if the file is in the cache
  set i [$Views($w,Scale) get]

  Log "Display $i"
  
  set p [lindex $Views($w,PhotoCache) $i]
  if { $p == "" } {
    set p [LoadCache $w $i]
  }
  if { $p == "" } {
    # Try again, some strange windows timing bug
    after 100
    set p [LoadCache $w $i]
  }
  
  set c $Views($w,Canvas)
  $c delete ImagePhoto
  # $c configure -image $p
  $c create image 0 0 -image $p -anchor nw -tags ImagePhoto
  $c configure -width [image width $p] -height [image height $p] -scrollregion [$c bbox all]
  Log "Width: [image width $p] Height: [image height $p]"
  update
}
    
    

proc UpdateSeriesInfo { w } {
  global Views

  set RowNumber [$Views($w,ExamList) selection get]
  if { $RowNumber == "" } { return }

  incr RowNumber -1
  set StudyInstanceUID [lindex [lindex $Views($w,StudySort) $RowNumber] end]
  set Views($w,CurrentStudyInstanceUID) $StudyInstanceUID
  $Views($w,SeriesList) delete 0 end

  set s $Views($w,$StudyInstanceUID,SeriesSort)
  set s [lsort -integer -index 0 $s]
  
  set Views($w,$StudyInstanceUID,SeriesSort) $s
  
  foreach Series $Views($w,$StudyInstanceUID,SeriesSort) {
    $Views($w,SeriesList) insert end [list [lindex $Series 0] [lindex $Series 1]]
  }
}

proc UpdateView { w } {
  global Views

  # Find the data for this view and plug it in
  set Views($w,Status) "Finding images..."
  set Dirs [FindDirectories [list $Views($w,Directory)]]
  set NumberOfDirs [llength $Dirs]
  set Count 1

  set Views($w,Status) "Sorting Images..."
  set Views($w,Progress) 0
  set ExamSort ""

  set Count 0
  set NumberOfDirs [llength $Dirs]
  Log $NumberOfDirs
  set Views($w,StudySort) ""
  set Views($w,Studies) ""
  
  foreach key [array names Views "$w,*,Series*"] {
    unset Views($key)
  }
  foreach Dir $Dirs {
    set Views($w,Progress) [expr 100 *  ( [incr Count] / double($NumberOfDirs) )]
    update

    # Find the first DICOM file
    foreach File [glob -nocomplain -- [file join $Dir *]] {
      array unset Tags
      set Answer [GetDicomTags $File [list {StudyID 1} {SeriesNumber 1} {StudyDescription ""}] \
                  [list StudyInstanceUID PatientsName PatientID StudyID StudyDate StudyDescription SeriesInstanceUID SeriesNumber SeriesDescription InstanceNumber]]
      if { $Answer == "" } { continue }
      array set Tags $Answer

      if { ![info exists ProcessedStudies($Tags(StudyInstanceUID))] } {
        # Add this to the Views
        set ProcessedStudies($Tags(StudyInstanceUID)) 1
        set Views($w,$Tags(StudyInstanceUID),Series) ""
        set Views($w,$Tags(StudyInstanceUID),SeriesSort) ""
        lappend Views($w,Studies) $Tags(StudyInstanceUID)
        lappend Views($w,StudySort) [list $Tags(PatientsName) $Tags(PatientID) $Tags(StudyID) $Tags(StudyDate) $Tags(StudyDescription) $Tags(StudyInstanceUID)]
      }

      if { ![info exists ProcessedSeries($Tags(SeriesInstanceUID))] } {
        set ProcessedSeries($Tags(SeriesInstanceUID)) 1
        lappend Views($w,$Tags(StudyInstanceUID),Series) $Tags(SeriesInstanceUID)
        lappend Views($w,$Tags(StudyInstanceUID),SeriesSort) [list $Tags(SeriesNumber) $Tags(SeriesDescription) $Tags(SeriesInstanceUID)]
      }
      # Just find the first good dicom file
      set Views($w,$Tags(SeriesInstanceUID),Directory) $Dir
      break
    }
  }

  set Views($w,Status) ""
  # Insert our data into the tables
  $Views($w,ExamList) delete 0 end
  foreach Study $Views($w,StudySort) {
    $Views($w,ExamList) insert end [list [lindex $Study 0] [lindex $Study 1] [lindex $Study 2] [clock format [clock scan [lindex $Study 3]] -format "%B %d, %Y"] [lindex $Study 4]]
  }
}
  

  
  
proc CreateViewDICOM { dir } {
  global Views
  InitViews
  
  # Create a viewer for a directory of images
  if { [info exists Views($dir)] } {
    raise $Views($dir)
    return;
  }
  
  set w .view[incr Views(Count)]

  # Init some things
  set Views($w,CurrentSeriesInstanceUID) ""
  set Views($w,PhotoCache) ""
  
  set Views($w,Directory) $dir
  toplevel $w -class ViewDICOM
  wm title $w "ViewDICOM: $dir"
  wm protocol $w WM_DELETE_WINDOW [list Close $w]

  set Menu [list \
            "&File" "" file 0 [list \
                                 [list command "Reload" {} "" {Ctrl r} -command "UpdateView $w"] \
                                 [list checkbutton "&Load images in background" {} "" {} -variable Views($w,LoadInBackground) ] \
                                 {separator} \
                                 [list command "Close" {} "" {Ctrl w} -command "Close $w"]
                              ] \
           ]
  Log $Menu
  
  set Views($w,MainFrame) [MainFrame $w.mainframe -menu $Menu -textvariable Views($w,Status) -progressvar Views($w,Progress) -progresstype normal -progressmax 100]
  $Views($w,MainFrame) showstatusbar progression


  pack $w.mainframe -fill both -expand 1
  set frame [$w.mainframe getframe]
  set pane [PanedWindow $frame.pane -side right]
  grid $pane -row 0 -sticky nsew
  grid columnconfigure $frame 0 -weight 1
  grid rowconfigure $frame 0 -weight 1
  grid rowconfigure $frame 1 -weight 0

  set viewpane [$pane add -weight 5].viewpane
  set pinfo [$pane add].pinfo
  set sinfo [$pane add].sinfo

  set tframe [TitleFrame $viewpane -text "Images"]
  pack $tframe -fill both -expand 1 -side top

  set f [frame [$tframe getframe].f]
  pack $f -fill both -expand 1
  
  set c [canvas $f.canvas -width 260 -height 260]
  set hs [scrollbar $f.hscroll -orient horizontal -command "$c xview"]
  set vs [scrollbar $f.vscroll -orient vertical -command "$c yview"]

  $c configure -xscrollcommand "$hs set" -yscrollcommand "$vs set"
  grid $c  -row 0 -column 0 -sticky nswe
  grid $vs -row 0 -column 1 -sticky ns
  grid $hs -row 1 -column 0 -sticky ew
  grid rowconfig $f 0 -weight 1
  grid columnconfig $f 0 -weight 1
  set sb [scale $f.scale -from 0 -to 100 -orient horizontal -command [list Display $w]]
  grid $sb -row 2 -column 0 -columnspan 2 -sticky ew
  set Views($w,Scale) $sb
  
  set Views($w,Canvas) $c
  
  set tframe [TitleFrame $pinfo -text "Patient Info"]
  pack $tframe -fill both -expand 1
  # set tframe [[$pane getframe].examframe getframe]
  # $pane pack first $tframe -fill both -expand 1
  
  set List [listcontrol [$tframe getframe].exam -selectmode single -onselect [list UpdateSeriesInfo $w] -height 5]
  set Views($w,ExamList) $List
  $List column insert Name end -text "Patient Name" -width 150
  $List column insert ID end -text "ID" -width 200
  $List column insert ExamDate end -text "Exam Date" -width 160
  $List column insert ExamNumber end -text "Exam Number" -width 75
  $List column insert Description end -text "Description" -width 400
  pack $List -fill both -expand 1 -padx 4 -pady 2

  set tframe [TitleFrame $sinfo -text "Series"]
  pack $tframe -fill both -expand 1
  # set tframe [$pane.seriespane getframe]
  # $pane pack second $tframe -fill both -expand 1

  set List [listcontrol [$tframe getframe].series -selectmode single -onselect [list View $w] -height 5]
  set Views($w,SeriesList) $List
  $List column insert Number end -text "\#" -width 50
  $List column insert Description end -text "Description" -width 400
  $List column insert Slices end -text "Slices" -width 75
  pack $List -fill both -expand 1 -padx 4 -pady 2

  update
  UpdateView $w
  return $w
}

if { 0 } {
  toplevel .view
  set f [tk_getOpenFile -title "Open DICOM Image"]
  set data [exec dcm2pnm --grayscale --write-raw-pnm --min-max-window-n $f > /tmp/Foo.pnm]
  set p [image create photo -file /tmp/Foo.pnm]


  set p [image create photo]
  set data [exec dcm2pnm --grayscale --write-raw-pnm --min-max-window-n $f]
  $p put $data

  set p [image create photo -data $data]
  
  set p [image create photo -file /tmp/Foo.bmp]
  pack [label .view.l -image $p] -fill both -expand 1

  # \
  source FetchDICOM.vfs/lib/app-FetchDICOM/ViewDICOM.tcl; set w [CreateViewDICOM /projects/spio/NeuroSync/GRCTesting-2007-07-31/vol1_073107/2007-07-31/MR1532/Series002/]

}
