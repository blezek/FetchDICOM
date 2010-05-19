package provide app-FetchDICOM 1.0
#!/usr/bin/env tclsh
# package require struct
package require Tk
package require mkWidgets
package require BWidget
package require struct
package require ViewDICOM

proc CollectBackground { fid ID UpdateProgress } {
  global Background Fetch
  if { [eof $fid] } {
    Log "ExecuteInBackground completed for $ID"
    set Background(Completed,$ID) 1
    set Background(Status,$ID) [catch { close $fid }]
  } else {
    if { [gets $fid Line] != -1 } {
      Log $Line
      set Fetch(Progress) [expr int ( $Fetch(Progress) + 1 ) % 100 ]
      append Background(Output,$ID) "$Line\n"
    }
  }
}


proc Help {} {
  package require Wikit
  Wikit::init [file join $starkit::topdir doc FetchDICOM.doc] 1 .help
}

proc StartViewDICOM {} {
  global Fetch
  set Directory [tk_chooseDirectory -initialdir $Fetch(FetchDirectory) -parent .fetch -title "Choose ViewDICOM directory"]
  if { $Directory == "" } { return }
  set Fetch(FetchDirectory) $Directory
  CreateViewDICOM $Directory
}



proc ExecuteInBackground { Command {UpdateProgress 0} } {
  # Start up a process, collect all the data, and return
  global Background

  set fid [open "| $Command" r]
  set ID [incr Background(Job)]
  Log "Job $ID: $Command"
  set Background(Output,$ID) ""
  set Background(Completed,$ID) 0
  fileevent $fid readable [list CollectBackground $fid $ID $UpdateProgress]
  vwait Background(Completed,$ID)

  set Output $Background(Output,$ID)
  unset Background(Output,$ID)
  set Status $Background(Status,$ID)
  return [list $Output $Status]
}
  

proc LogCheckAction {} {
    global Fetch
    SavePreferences
    if { !$Fetch(SaveLog) } {
        if { [winfo exists .fetch.log] } {
            destroy .fetch.log
        }
    } else {
        Log ""
    }
}

proc Log { Text } {
  global Fetch
    if { ![winfo exists .fetch] } { return }
    if { $Fetch(SaveLog)} {
      if { ![winfo exists .fetch.log] } {
          # Create the log window
        set w [toplevel .fetch.log -class FetchDICOM]

	wm title $w "FetchDICOM - Log"
        set f [frame $w.frame]
        set vs [scrollbar $f.yscroll -orient vert -command "$f.text yview"]
        set txt [text $f.text -yscrollcommand "$vs set"]
        set Fetch(LogWindow) $txt
        pack $vs -fill y -side right
        pack $txt -expand yes -fill both -side left
        pack $f -fill both -expand 1 -side top
        set f [frame $w.bottom]
        pack [button $f.clear -text Clear -command "$txt delete 1.0 end"] -side left
        pack [button $f.close -text Close -command "set Fetch(SaveLog) 0; LogCheckAction"] -side left
        pack $f -side top -anchor n
        wm group .fetch.log .fetch
          raise .fetch.log
          wm protocol .fetch.log WM_DELETE_WINDOW { set Fetch(SaveLog) 0; LogCheckAction }
      }
      $Fetch(LogWindow) insert end "$Text\n"
  }
}

proc DCMTK { Command } {
    global tcl_platform Fetch
    switch -glob -- $tcl_platform(os) {
	"*Windows*" {
	    # return $Command
	    return [list [file join $Fetch(DCMTKPath) $Command.exe]]
	}
	default {
	    return $Command
	}
    }
}

proc SetDCMTKPath {} {
    global tcl_platform Fetch
    if { [string match *Windows* $tcl_platform(os)] } {

	set Fetch(DCMTKPath) [file join [file dir [info nameofexecutable]] dcmtk/bin]

    } else {
	set Fetch(DCMTKPath) ""
    }
    Log "DCMTKPath: $Fetch(DCMTKPath)"
}

proc LoadPreferences {} {
  global AE Fetch env

  if { ![file exists [file join $env(HOME) .dicomfetch] ] } {
    # Kick it off
    SavePreferences 1
  }
  
  set fid [open [file join $env(HOME) .dicomfetch] r]
  array set Fetch [gets $fid]
  array set AE [gets $fid]
  close $fid

}

proc SavePreferences {{incallback 0}} {
  global AE Fetch env
  if { ![info exist Fetch(IdleCallback)] || $Fetch(IdleCallback) == "" } {
    set Fetch(IdleCallback) [after 400 "SavePreferences 1"]
  }
  if { !$incallback } {
    return
  }
  set Fetch(IdleCallback) ""
  catch { 
    set Fetch(WindowGeometry) [wm geom .fetch]
  }
  set fid [open [file join $env(HOME) .dicomfetch] "w"]
  puts $fid [array get Fetch]
  puts $fid [array get AE]
  close $fid
}
  
proc Initialize {} {
  global AE Fetch env Background
  set AE(localhost) [list localhost localhost 4006]
  set AE(aware) [list aware aware.crd.ge.com 4006]
  set AE(cdp1_ow0) [list cdp1_ow0 cdp1_ow0.crd.ge.com 4006]
  set AE(signa2_ow0) [list signa2_ow0 signa2_ow0.crd.ge.com 4006]
  set AE(signa3_ow0) [list signa3_ow0 signa3_ow0.crd.ge.com 4006]

  set Fetch(CallingAE) localhost
  set Fetch(CalledAE) aware
  # Add the local machine if we can...
  if { [info exists env(COMPUTERNAME)] } {
    set cn [string tolower $env(COMPUTERNAME)]
    set AE($cn) [list $cn $cn 4006]
    set Fetch(CallingAE) $cn
  }

  set Fetch(Completed) 1
  set Fetch(Remaining) 1
  set Fetch(Done) 0
  set Fetch(SortFetchedImages) ExamSeriesImage
  set Fetch(SortExamBy) 0
  set Fetch(SortExamDirection) -increasing
  set Fetch(FetchDirectory) ""
  set Fetch(CSVFile) ExamReport.csv
  set Fetch(DICOMFile) Foo.dcm
  set Fetch(SaveLog) 0
  set Fetch(ShowSliceCounts) 1
  set Fetch(Progress) 0
  set Fetch(WindowGeometry) 800x650

  LoadPreferences
  SetDCMTKPath

  set Fetch(Queue) [::struct::queue]
  set Fetch(Status) "Welcome to FetchDICOM!"
  set Fetch(Fetching) 0
  set Fetch(QuickSortForPush) 1

  # For background jobs
  set Background(Job) 0
  
  wm withdraw .
  # {command "Save Contact Sheet..." {} "Find DICOM files and generate a Contact Sheet" {} -command ContactSheet }
  set Menu {
    "&File" "" file 0 {
      {command "Update" {} "" {Ctrl u} -command GetExamInfo }
      {command "ViewDICOM" {} "" {Ctrl v} -command StartViewDICOM }
      {separator}
      {command "Show Tags..." {} "" {Ctrl t} -command DisplayDicomTags }
      {command "Save as CSV..." {} "Save exam report as CSV file" {} -command SaveAsCSV }
      {separator}
      {checkbutton "&Log" {} "Log commands to stdout" {Ctrl o} -variable Fetch(SaveLog) -command LogCheckAction }
      {checkbutton "&Show Slice Counts" {} "Show slice counts" {Ctrl s} -variable Fetch(ShowSliceCounts) }
      {separator}
      {command "Console" {} "" {Ctrl c} -command ShowConsole }
      {separator}
      {command "Quit" {} "Quit" {Ctrl q} -command Quit }
    }
    "&Fetch" "" queue 0 {
      {command "Fetch" {} "Fetch the selected images from the server" {Ctrl f} -command {Fetch} }
      {cascad "&Sort" "" sort 0 {
        {radiobutton "Exam/Series/Image\#\#\#\#.dcm" {} "Sort the fetched images by exam, series, and image" {Ctrl 1} -value ExamSeriesImage -variable Fetch(SortFetchedImages) }
        {radiobutton "PatientName/Series/Image\#\#\#\#.dcm" {} "Sort the fetched images by patient name, series, and image" {Ctrl 2} -value PatientNameSeriesImage -variable Fetch(SortFetchedImages) }
        {radiobutton "Fancy sort" {} "Sort the fetched images by Name, Date, exam, series" {Ctrl 3} -value Fancy -variable Fetch(SortFetchedImages) }
        {radiobutton "Exam PatientName/Series/Image\#\#\#\#.dcm" {} "Sort the fetched images by concatination of exam number and patient name, series, and image" {Ctrl 4} -value ExamPatientNameSeriesImage -variable Fetch(SortFetchedImages) }
        {radiobutton "ExamStation/Series/Image\#\#\#\#.dcm" {} "Sort the fetched images by exam/station, series, and image" {Ctrl 5} -value ExamStationSeriesImage -variable Fetch(SortFetchedImages) }
        {radiobutton "PatientID/Series/Image\#\#\#\#.dcm" {} "Sort the fetched images by patient ID, series, and image" {Ctrl 6} -value PatientIDSeriesImage -variable Fetch(SortFetchedImages) }
        {radiobutton "Modality/Station/Exam/Series/Image\#\#\#\#.dcm" {} "Sort the fetched images by modality, station, exam, series, and image" {Ctrl 7} -value ModalityStationExamSeriesImage -variable Fetch(SortFetchedImages) }
        {radiobutton "Modality/Exam/Series/Image\#\#\#\#.dcm" {} "Sort the fetched images by station, exam, series, and image" {Ctrl 8} -value ModalityExamSeriesImage -variable Fetch(SortFetchedImages) }
        {radiobutton "Image\#\#\#\#.dcm" {} "Sort the fetched images by image" {Ctrl 9} -value Image -variable Fetch(SortFetchedImages) }
        {radiobutton "Exam/Series/Phase/Image\#\#\#\#.dcm" {} "Sort the fetched images by exam, series, cardiac phase and image" {Ctrl 0} -value ExamSeriesPhaseImage -variable Fetch(SortFetchedImages) }
        {radiobutton "Exam/Series/Location/Image\#\#\#\#.dcm" {} "Sort the fetched images by exam, series, location and image" {} -value ExamSeriesLocationImage -variable Fetch(SortFetchedImages) }
      }
      }
    }
    "&Sort" "" sort 0 {
      {radiobutton "Patient Name" {} "Sort by patient name" {Ctrl n} -value 0 -variable Fetch(SortExamBy) -command SortAndDisplay }
      {radiobutton "Patient ID" {} "Sort by patient id" {Ctrl i} -value 1 -variable Fetch(SortExamBy) -command SortAndDisplay }
      {radiobutton "Exam Number" {} "Sort by exam number" {Ctrl e} -value 2 -variable Fetch(SortExamBy) -command SortAndDisplay }
      {radiobutton "Study Date" {} "Sort by exam date" {Ctrl d} -value 3 -variable Fetch(SortExamBy) -command SortAndDisplay }
      {separator}
      {radiobutton "Increasing" {} "Sort increasing" {} -value "-increasing" -variable Fetch(SortExamDirection) -command SortAndDisplay }
      {radiobutton "Decreasing" {} "Sort decreasing" {} -value "-decreasing" -variable Fetch(SortExamDirection) -command SortAndDisplay }
    }
    "&Push" "" push 0 {
      {command "Push Directory" {} "Push all files in a directory to the server" {Ctrl p} -command {PushImages} }
      {checkbutton "&Quick Sorting" {} "Try to send all files in the directory" {} -variable Fetch(QuickSortForPush) }
      {command "Sort Local Files" {} "Sort local files" {Ctrl l} -command {SortLocalFiles} }
    }
    "&Help" "" help 0 {
      {command "About" {} "" {} -command About }
      {command "Help" {} "" {Ctrl h} -command Help }
    }
  }


  toplevel .fetch -class FetchDICOM
  wm title .fetch "FetchDICOM"
  wm geometry .fetch $Fetch(WindowGeometry)
  update

  # Handle quit events and geometry
  wm protocol .fetch WM_DELETE_WINDOW Quit
  bind .fetch <Configure> +SavePreferences
  
  set Fetch(MainFrame) [MainFrame .fetch.mainframe -menu $Menu -textvariable Fetch(Status) -progressvar Fetch(Progress) -progresstype normal -progressmax 100 ]
  pack .fetch.mainframe -fill both -expand 1
  .fetch.mainframe showstatusbar progression
  set frame [.fetch.mainframe getframe]

  set pane [PanedWindow $frame.pane -side right]
  # set pane [pane $frame.pane -orientation horizontal -resize both -width 5]
  
  # pack $pane -expand 1
  # pack $f -fill x 
  grid $pane -row 0 -sticky nsew
  grid columnconfigure $frame 0 -weight 1
  grid rowconfigure $frame 0 -weight 1
  grid rowconfigure $frame 1 -weight 0

  set pinfo [$pane add].pinfo
  set sinfo [$pane add].sinfo
  
  set tframe [TitleFrame $pinfo -text "Patient Info"]
  pack $tframe -fill both -expand 1
  # set tframe [[$pane getframe].examframe getframe]
  # $pane pack first $tframe -fill both -expand 1
  
  set List [listcontrol [$tframe getframe].exam -selectmode multiple -onselect GetSeriesInfo]
  set Fetch(ExamList) $List
  $List column insert Name end -text "Patient Name" -width 150 -minsize 10
  $List column insert ID end -text "ID" -width 200  -minsize 10
  $List column insert ExamDate end -text "Exam Date" -width 160  -minsize 10
  $List column insert ExamNumber end -text "Exam Number" -width 75  -minsize 10
  $List column insert Description end -text "Description" -width 400  -minsize 10
  pack $List -fill both -expand 1 -padx 4 -pady 2

  foreach c [list Name ID  ExamNumber ExamDate Description] idx "0 1 2 3 4" {
    $List column bind $c <Double-1> [list catch [list $List column fit $c]]
    $List column bind $c <1> "SortAndDisplay $idx"
  }

  set tframe [TitleFrame $sinfo -text "Series"]
  pack $tframe -fill both -expand 1
  # set tframe [$pane.seriespane getframe]
  # $pane pack second $tframe -fill both -expand 1

  set List [listcontrol [$tframe getframe].series]
  set Fetch(SeriesList) $List
  $List column insert Number end -text "\#" -width 50
  $List column insert Description end -text "Description" -width 400
  $List column insert Slices end -text "Slices" -width 75
  pack $List -fill both -expand 1 -padx 4 -pady 2

  set f [frame $frame.ae]
  pack [label $f.serverl -text "Server:"] -side left
  pack [combobox $f.server -lines 10 -state restricted -entries [lsort [array names AE]] -textvariable Fetch(CalledAE)] -side left

  pack [label $f.locall -text "Local:"] -side left
  pack [combobox $f.local -lines 10 -state restricted -entries [lsort [array names AE]] -textvariable Fetch(CallingAE)] -side left
  $f.local see [lsearch [lsort [array names AE]] $Fetch(CallingAE)]
  pack [button $f.configure -text "Configure" -command ConfigureAE] -side left

  grid $f -row 1 -sticky ew

  set Fetch(CalledAEComboBox) $f.server
  set Fetch(CalledAEComboBox) $f.server
  set Fetch(CallingAEComboBox) $f.local
  update
  $Fetch(CalledAEComboBox) configure -command GetExamInfo
  $f.server see [lsearch [lsort [array names AE]] $Fetch(CalledAE)]
  
}

proc Quit {} {
  if { [tk_messageBox -parent .fetch -title "Quit FetchDICOM?" -message "Really quit FetchDICOM?" -type yesno -icon question] == "yes" } {
    SavePreferences 1
    exit
  }
}

proc ConfigureAE {} {
  global AE AETemp
  # Make a dialog

  Dialog .fetch.configureae -modal local -parent .fetch -cancel 3
  .fetch.configureae add -text "New" -command NewAE
  .fetch.configureae add -text "Modify" -command ModifyAE
  .fetch.configureae add -text "Delete" -command DeleteAE
  .fetch.configureae add -text "Done"

  set AETemp(Dialog) .fetch.configureae
  set AETemp(List) [listcontrol [$AETemp(Dialog) getframe].ae]
  $AETemp(List) column insert AE end -text "Application Entity"

  PopulateAE
  
  pack $AETemp(List) -fill both -expand 1
  
  .fetch.configureae draw
  destroy .fetch.configureae
  return
}

proc DeleteAE {} {
  global AE Fetch AETemp
  set Row [$AETemp(List) selection get]
  if { $Row == "" } { return }
  set Entry [lindex [lsort [array names AE]] [incr Row -1]]
  if { [tk_messageBox -parent $AETemp(Dialog) -title "Delete Application Entity" -message "Delete Application Entity $Entry?" -type yesno] == "yes" } {
    unset AE($Entry)
    if { [llength [array names AE]] == 0 } {
      set AE(localhost) [list localhost localhost 4006]
    }
    if { $Fetch(CalledAE) == $Entry } {
      set Fetch(CalledAE) [lindex [lsort [array names AE]] 0]
    }
    if { $Fetch(CallingAE) == $Entry } {
      set Fetch(CallingAE) [lindex [lsort [array names AE]] 0]
    }
  }
  PopulateAE
}
  

  
proc PopulateAE {} {
  global AE AETemp Fetch
  $AETemp(List) delete 0 end
  set Names [lsort [array names AE]]
  foreach Item $Names {
    $AETemp(List) insert end $Item
  }
  $Fetch(CallingAEComboBox) configure -entries $Names
  $Fetch(CallingAEComboBox) see [lsearch [lsort [array names AE]] $Fetch(CallingAE)]
  $Fetch(CalledAEComboBox) configure -entries $Names
  $Fetch(CalledAEComboBox) see [lsearch [lsort [array names AE]] $Fetch(CalledAE)]
  SavePreferences
  
}

proc NewAE {} {
  global AE AETemp
  set D [Dialog .fetch.newae -modal local -parent $AETemp(Dialog) -cancel 1 -default 0 -title "New Application Entity"]
  .fetch.newae add -text "OK" 
  .fetch.newae add -text "Cancel" 
  set f [$D getframe]
  pack [LabelEntry $f.host -label Name: -textvariable AETemp(Name)] -side top
  set AETemp(Name) ""

  set DoModify 0
  set Entry ""
  if { [$D draw] == 0 } {
    set Entry $AETemp(Name)
    if { $Entry != "" && ![info exist AE($Entry)] } {
      set AE($Entry) [list $Entry $Entry 4006]
      set DoModify 1
    }
  }
  destroy $D
  if { $DoModify } { ModifyAE $Entry }
  PopulateAE
}
  

proc ModifyAE { {Entry {} } } {
  global AE AETemp
  if { $Entry == {} } {
    set Row [$AETemp(List) selection get]
    if { $Row == "" } { return }
    set Entry [lindex [lsort [array names AE]] [incr Row -1]]
  }
  
  set D [Dialog .fetch.modifyae -modal local -parent $AETemp(Dialog) -cancel 1 -default 0 -title "Modify $Entry"]
  .fetch.modifyae add -text "OK" 
  .fetch.modifyae add -text "Cancel" 
  set f [$D getframe]
  pack [LabelEntry $f.host -label Host: -textvariable AETemp(Host)] -side top
  pack [LabelEntry $f.port -label Port: -textvariable AETemp(Port)] -side top
  set AETemp(Host) [lindex $AE($Entry) 1]
  set AETemp(Port) [lindex $AE($Entry) 2]

  if { [$D draw] == 0 } {
    set AE($Entry) [list $Entry $AETemp(Host) $AETemp(Port)]
  }
  destroy $D
  PopulateAE
}


proc PushImages {} {
  global Fetch AE

  set Directory [tk_chooseDirectory -initialdir $Fetch(FetchDirectory) -parent .fetch -title "Choose directory"]
  if { $Directory == "" } { return }

  ProgressDlg .fetch.pushprogress -parent .fetch -title "Push Images..." \
  -maximum 100 -width 40 -variable Fetch(Progress) -stop {} \
  -textvariable Fetch(Status)
  update
  set Fetch(Status) "Sorting images..."
  set Files [WalkDirectory [list $Directory]]
  set Fetch(FetchDirectory) $Directory
  SavePreferences
  
  set total [llength $Files]
  set count 0
  set DICOMFiles ""
  foreach File $Files {
    set Fetch(Progress) [expr 100 * [incr count] / double($total)]
    update
    if { $Fetch(QuickSortForPush) } {
      lappend DICOMFiles [file nativename $File]
    } else {      
      if { [llength [GetDicomTags $File]] } {
        lappend DICOMFiles [file nativename $File]
      }
    }
  }
  
  set Fetch(NumberOfFiles) [llength $DICOMFiles]
  set Fetch(PushedFiles) 0
  if { $Fetch(NumberOfFiles) == 0 } { 
      destroy .fetch.pushprogress
      tk_messageBox -message "Did not find any DICOM images to push" -type ok
      return
 }
  
  set CallingAE $AE($Fetch(CallingAE))
  set CalledAE  $AE($Fetch(CalledAE))

  # Form the storescu command
  set Command "| [DCMTK storescu] -v --aetitle [lindex $CallingAE 0]"
  append Command " --call [lindex $CalledAE 0]"
  append Command " [lindex $CalledAE 1] [lindex $CalledAE 2] "
  set BaseCommand $Command

  # tk_messageBox -message "Pushing [llength $DICOMFiles]" -type ok
  
  while { [llength $DICOMFiles] > 0 } {
    # Push 100 at a time
    set Command $BaseCommand
    append Command " [lrange $DICOMFiles 0 99]"
    set DICOMFiles [lrange $DICOMFiles 100 end]
    set Fetch(Status) "Sending files..."
    set fid [open $Command "r"]
    fconfigure $fid -buffering line 
    fileevent $fid readable [list HandlePush $fid]
    vwait Fetch(Done)
    catch { close $fid }
  }
  set Fetch(Progress) 0
  destroy .fetch.pushprogress
  GetExamInfo
}
  
proc HandlePush { fid } {
  global Fetch

  if { ![eof $fid] } {
    set Line [gets $fid]
    Log $Line
    if { [string match "*Sending file:*" $Line] } {
      incr Fetch(PushedFiles)
      set Fetch(Status) "Sending ($Fetch(PushedFiles)/$Fetch(NumberOfFiles)): [string range $Line 14 end]"
    }
    set Fetch(Progress) [expr 100 * $Fetch(PushedFiles) / $Fetch(NumberOfFiles)]
  } else { 
      set Fetch(Done) 1
  }
}
  
  


proc GetSeriesInfo {} {
  global Fetch ExamData AE SeriesData Sort

  set RowNumber [$Fetch(ExamList) selection get]
  if { $RowNumber == "" } { return }
  if { [llength $RowNumber] > 1 } {
    $Fetch(SeriesList) delete 0 end
    return
  }
  incr RowNumber -1

  set UID [lindex [lindex $Sort(ExamSort) $RowNumber] end]

  array set Exam $ExamData($UID)
  
  set CallingAE $AE($Fetch(CallingAE))
  set CalledAE  $AE($Fetch(CalledAE))
  # Run findscu to get data
  set Command "[DCMTK findscu] "
  append Command " --aetitle [lindex $CallingAE 0]"
  append Command " --call [lindex $CalledAE 0] -S "
  append Command " --key 0008,0052=SERIES  --key 0020,000e --key 0008,0060 --key 0020,000d=$UID --key 0020,0011 --key 0008,0060 --key 0008,0016 --key 0008,103e"
  append Command " [lindex $CalledAE 1] [lindex $CalledAE 2] |& tee Log.txt"
  Log $Command
  if { [catch {
    # set Data [eval exec $Command]
    set Data [lindex [ExecuteInBackground $Command] 0]
  } Result ] } {
    tk_messageBox -parent .fetch -title "Error" -message "Failed to connect to server: [lindex $CalledAE 1]" -type ok -icon error
    $Result
    return
  }

  set Responses [GetResponses $Data]
  
  array unset SeriesData
  set SeriesSort ""
  foreach Response $Responses {
    array unset E
    array set E [GetTags $Response [list SeriesNumber SeriesDescription]]
    set E(StudyInstanceUID) $Exam(StudyInstanceUID)
    set SeriesData($E(SeriesInstanceUID)) [array get E]
    lappend SeriesSort [list "$E(SeriesNumber)" $E(SeriesInstanceUID)]
  }
  set SeriesSort [lsort -dictionary -index 0 $SeriesSort]
  $Fetch(SeriesList) delete 0 end
  foreach EE $SeriesSort {
    array unset E
    array set E $SeriesData([lindex $EE 1])
    $Fetch(SeriesList) insert end [list $E(SeriesNumber) $E(SeriesDescription) 0]
  }

  set Sort(SeriesSort) $SeriesSort

  if { $Fetch(ShowSliceCounts) } {
    # Find the number of slices
    set Row 1
    set NumberOfSeries [llength $SeriesSort] 
    foreach EE $SeriesSort {
      array unset E
      array set E $SeriesData([lindex $EE 1])
      set Command "[DCMTK findscu]"
      append Command " --aetitle [lindex $CallingAE 0]"
      append Command " --call [lindex $CalledAE 0] -S "
      append Command " --key 0008,0052=IMAGE"
      append Command " --key 0020,000d=$E(StudyInstanceUID)"
      append Command " --key 0020,000e=$E(SeriesInstanceUID)"
      append Command " --key 0008,0018"
      append Command " [lindex $CalledAE 1] [lindex $CalledAE 2]"
      # set Data [eval exec $Command]
      set r [ExecuteInBackground $Command]
      set Data [lindex $r 0]
      Log $Data
      set Responses [GetResponses $Data]
      Log "Found [llength $Responses] Slices!"
      set E(SliceCount) [llength $Responses]
      $Fetch(SeriesList) set -columns Slices $Row $E(SliceCount)
      set SeriesData($E(SeriesInstanceUID)) [array get E]
      set Fetch(Progress) [expr 100 * ( $Row / double($NumberOfSeries))]
      incr Row
      update
      
      set NewRowNumber [$Fetch(ExamList) selection get]
      if { $NewRowNumber == "" } { return }
      if { [incr NewRowNumber -1] != $RowNumber } { return }
    }
  }
  
}
  


proc GetResponses { Data } {
      
  set Responses ""
  set Accum ""
  foreach Line [split $Data "\n"] {
    if { [string match "W: *" $Line] } {
      set Line [string range $Line 3 end]
      Log $Line
    }
    if { [string match -------- $Line] } {
      lappend Responses $Accum
      set Accum ""
    } else {
      lappend Accum $Line
    }
  }
  return $Responses
}


      
proc GetTags { Response {RequiredTags ""} } {
  array unset E
  foreach Item $Response {
    if { [regexp {\[([^\]]+)\]\W+\#\W+\d+,\W+\d+ (\w+)} $Item foo Value Tag] } {
      set E($Tag) $Value
    }
  }
  foreach Required $RequiredTags {
    if { ![info exists E($Required)] } { set E($Required) "" }
  }
  return [array get E]
}

proc GetExamInfo {} {
  global Fetch ExamData AE Sort

  set CallingAE $AE($Fetch(CallingAE))
  set CalledAE  $AE($Fetch(CalledAE))
  # Run findscu to get data from aware
    set Command "[DCMTK findscu]"
    append Command " --aetitle [lindex $CallingAE 0]"
  append Command " --call [lindex $CalledAE 0]"
  append Command " -S --key 0008,0052=STUDY "
  append Command " --key 0008,0020 "
  append Command " --key 0008,0030 "
  append Command " --key 0008,0054 "
  append Command " --key 0008,1030 "
  append Command " --key 0010,0010 "
  append Command " --key 0010,0020 "
  append Command " --key 0010,0030 "
  append Command " --key 0020,000d "
  append Command " --key 0020,0010 "

  # append Command " -S --key 0008,0052=STUDY "
  #  append Command " --key 0008,0020 --key 0008,0030 --key 0008,1030 --key 0020,0010 --key 0020,000d --key 0010,0010 --key 0010,0020 --key 0008,103e --key 0008,0060"
  append Command " [lindex $CalledAE 1] [lindex $CalledAE 2] |& tee Log.txt"
  Log $Command
  set Fetch(Status) "Fetching exam list from [lindex $CalledAE 0]"

  set w [toplevel .fetch.grab -class Dialog]
  wm title $w "Updating display"
  wm iconname $w Dialog
  wm protocol $w WM_DELETE_WINDOW { }
  wm transient $w .fetch
  pack [label $w.label -text "Fetching exam list from [lindex $CalledAE 0]"] -side left
  pack [label $w.icon -bitmap hourglass] -side left
  wm withdraw $w
  ::tk::PlaceWindow $w widget .fetch
  wm deiconify $w
  raise $w
  grab set $w
  Log "Grabbing"
  set Status 1
    if { [catch {
      # set Data [eval exec $Command]
      set r [ExecuteInBackground $Command 1]
      Log "Finished ExecuteInBackground $r"
      set Data [lindex $r 0]
      set Status [lindex $r 1]
      Log $Status
      Log $Data
    } Result ] } {
        grab release $w
      tk_messageBox -parent .fetch -title "Error" -message "Error connecting to server: [lindex $CalledAE 0]\n$Command\n$Result" -type ok -icon error
      Log $Result
        destroy $w
	return
    }
        grab release $w
        destroy $w
	
    if { $Status } {
      tk_messageBox -parent .fetch -title "Error" -message "Error connecting to server: [lindex $CalledAE 0]\n\nThis often means the server is unavailable\n\n$Command\n$Data" -type ok -icon error
        return
    }

  set Responses [GetResponses $Data]
  
  array unset ExamData
  set ExamSort ""
  foreach Response $Responses {
    array set E [GetTags $Response [list StudyID PatientsName StudyDate StudyDescription]]
    set ExamData($E(StudyInstanceUID)) [array get E]
    lappend ExamSort [list $E(PatientsName) $E(PatientID) $E(StudyID) $E(StudyDate) $E(StudyInstanceUID)]
  }
  set Sort(AllExamSort) $ExamSort
  SortAndDisplay
}

proc SaveAsCSV { {Filename {} } } {
  global Fetch ExamData Sort

  if { $Filename == {} } {
    set Filename [tk_getSaveFile -initialdir $Fetch(FetchDirectory) -initialfile $Fetch(CSVFile) -parent .fetch -title "Save Exam list as CSV" -filetypes [list [list CSV {.csv}] [list {All Files} *]]]
  }
  if { $Filename == {} } { return }
  set Fetch(FetchDirectory) [file dir $Filename]
  set Fetch(CSVFile) [file tail $Filename]
  

  # Sort by exam number first, the selected
  set t [lsort -dictionary -index 2 $Fetch(SortExamDirection) $Sort(AllExamSort)]
  if { $Fetch(SortExamBy) != 2 } { 
    set ExamSort [lsort -dictionary -index $Fetch(SortExamBy) $Fetch(SortExamDirection) $t]
  } else {
    set ExamSort $t
  }
    
  set fid [open $Filename "w"]
  puts $fid "Patient Name, ID, Exam Date, Exam Number, Description"
  
  foreach EE $ExamSort {
    array set E $ExamData([lindex $EE end])
    
    puts $fid "\"$E(PatientsName)\",\"$E(PatientID)\",\"[clock format [clock scan $E(StudyDate)] -format "%B %d, %Y"]\",\"$E(StudyID)\",\"$E(StudyDescription)\""
  }
  SavePreferences
}
  

proc SortAndDisplay { {idx ""} } {
  global Fetch ExamData Sort
  if { ![info exists Sort(AllExamSort)] } { return }

  if { $idx != "" } {
    Log "SortAndDisplay $idx: current is $Fetch(SortExamBy)"
    # User pressid this button
    if { $idx != $Fetch(SortExamBy) } {
      set Fetch(SortExamBy) $idx
    } else {
      # Toggle sort direction
      if { $Fetch(SortExamDirection) == "-increasing" } {
        set Fetch(SortExamDirection) -decreasing
      } else {
        set Fetch(SortExamDirection) -increasing
      }
    }
    Log "SortAndDisplay $idx $Fetch(SortExamDirection)"
  }
  
  # Sort by exam number first, the selected
  set t [lsort -dictionary -index 2 $Fetch(SortExamDirection) $Sort(AllExamSort)]
  if { $Fetch(SortExamBy) != 2 } { 
    set ExamSort [lsort -dictionary -index $Fetch(SortExamBy) $Fetch(SortExamDirection) $t]
  } else {
    set ExamSort [lsort -integer -index $Fetch(SortExamBy) $Fetch(SortExamDirection) $t]
  }
  $Fetch(ExamList) delete 0 end
  foreach EE $ExamSort {
    array set E $ExamData([lindex $EE end])
    $Fetch(ExamList) insert end [list $E(PatientsName) $E(PatientID) [clock format [clock scan $E(StudyDate)] -format "%B %d, %Y"] $E(StudyID) $E(StudyDescription)]
  }
  set Sort(ExamSort) $ExamSort
  SavePreferences
}


proc Fetch { } {
  global Fetch ExamData AE SeriesData Sort

  set RowNumber [$Fetch(ExamList) selection get]
  if { [$Fetch(SeriesList) selection get] != "" } { set RowNumber "" }
  if { $RowNumber == "" } {
    set RowNumber [$Fetch(SeriesList) selection get]
    Log "Series $RowNumber"
    if { $RowNumber == "" } {
      tk_messageBox -parent .fetch -title "No selection" -message "Please select a patient exam or series before trying to fetch" -icon warning -type ok
      return
    }
    set Command(Type) Series
    set Commands ""
    foreach RN $RowNumber {
      incr RN -1
      lappend Commands $SeriesData([lindex [lindex $Sort(SeriesSort) $RN] 1])
    }
  } else {
    set Command(Type) Exam
    set Commands ""
    foreach RN $RowNumber {
      incr RN -1
      lappend Commands $ExamData([lindex [lindex $Sort(ExamSort) $RN] end])
    }
  }

  set Directory [tk_chooseDirectory -initialdir $Fetch(FetchDirectory) -parent .fetch -title "Save images"]
  if { $Directory == "" } { return }


  set Fetch(FetchDirectory) $Directory
  SavePreferences

  set Command(Directory) $Directory
  
  set Command(CallingAE) $AE($Fetch(CallingAE))
  set Command(CalledAE)  $AE($Fetch(CalledAE))
  set Command(SortFetchedImages) $Fetch(SortFetchedImages)
  # set DestinationAE $AE($Fetch(DestinationAE))

  if { $Command(Type) == "Series" } {
    foreach C $Commands {
      set Command(Series) $C
      $Fetch(Queue) put [array get Command]
    }
  } else {
    # Loop over all the commands
    foreach C $Commands {
      set Command(Exam) $C
      $Fetch(Queue) put [array get Command]
    }
  }
  BackgroundFetch
}

proc BackgroundFetch {} {
  global Fetch ExamData AE SeriesData Sort
  
  if { $Fetch(Fetching) } { return }
  set Fetch(Fetching) 1
  while { [$Fetch(Queue) size] } {
    array set FetchCommand [$Fetch(Queue) get]

    # Pull out some variables
    set Directory $FetchCommand(Directory)
    set CallingAE $FetchCommand(CallingAE)
    set CalledAE $FetchCommand(CalledAE)
    set SortType $FetchCommand(SortFetchedImages)

    switch $FetchCommand(Type) {
      Series {
        array set Series $FetchCommand(Series)
      }
      Exam {
        array set Exam $FetchCommand(Exam)
      }
    }
    
    # Start the server
    file mkdir $Directory

    set i 0
    while { 1 } {
      set Temp [file join $Directory [format Temp%d $i]]
      if { ![file exists $Temp] } { break }
      incr i
    }
    file mkdir $Temp

    # Form the move statement
    # Run findscu to get data from aware
    set Command "[DCMTK movescu] -v -S --port [lindex $CallingAE 2] --aetitle [lindex $CallingAE 0]"
    append Command " --call [lindex $CalledAE 0]"
    append Command " --move [lindex $CallingAE 0]"

    switch $FetchCommand(Type) {
      Exam {
        append Command " --key 0008,0052=STUDY"
        append Command " --key 0020,000d=$Exam(StudyInstanceUID)"
      }
      Series {
        append Command " --key 0008,0052=SERIES"
        append Command " --key 0020,000e=$Series(SeriesInstanceUID)"
        append Command " --key 0020,000d=$Series(StudyInstanceUID)"
      }
    }
    append Command " [lindex $CalledAE 1] [lindex $CalledAE 2]"

    if { ![winfo exists .fetch.progressdlg] } {
      ProgressDlg .fetch.progressdlg -parent .fetch -title "Fetching Images..." \
      -maximum 100 -width 40 -variable Fetch(Progress) -stop {} \
      -textvariable Fetch(Status)
	# -modal none
    }

    set OldDir [pwd]
    cd $Temp
    set Fetch(Status) "Fetching Images from server"
    Log $Command

    set fid [open "| $Command" "r"]
    cd $OldDir
  
    # fconfigure $fid -buffering line -blocking 0 -buffersize 100 -translation auto
    # fconfigure $fid -buffering line -blocking 1 -buffersize 10
    # fconfigure $fid -buffering line
    set Fetch(FetchStatus) ""
    fileevent $fid readable [list HandleMove $fid]

    vwait Fetch(Done)
    if { [catch { close $fid } Result] } {
      set answer [tk_messageBox -parent .fetch -title "Error" -message "Failed to fetch from Server: [lindex $CalledAE 1]\nChoose OK to continue, Cancel to delete remaining jobs.\n$Result" -type okcancel -icon error]
      if { $answer == "cancel" } {
        $Fetch(Queue) clear
      }
    }
    # Sort the fetched images
    SortFetchedImages $Directory $Temp $SortType
  }

  destroy .fetch.progressdlg
  set Fetch(Status) ""
  set Fetch(Fetching) 0
}

proc SortLocalFiles {} {
  global Fetch AE

  set Directory [tk_chooseDirectory -initialdir $Fetch(FetchDirectory) -parent .fetch -title "Choose files to sort"]
  if { $Directory == "" } { return }

  ProgressDlg .fetch.pushprogress -parent .fetch -title "Sort Local Images..." \
  -maximum 100 -width 40 -variable Fetch(Progress) -stop {} \
  -textvariable Fetch(Status)
  update
  set Fetch(Status) "Finding images..."
  set Files [WalkDirectory [list $Directory]]
  set Fetch(FetchDirectory) $Directory
  SavePreferences

  set Directory [tk_chooseDirectory -initialdir $Fetch(FetchDirectory) -parent .fetch -title "Sort and save into"]
  if { $Directory == "" } { return }
  set Fetch(FetchDirectory) $Directory
  SortFetchedImages $Directory $Files
  destroy .fetch.pushprogress

}

proc SortFetchedImages { Directory Temp {Sort {}} } {
  global Fetch

  set Move 1
  if { [llength $Temp] == 1 } {
    set Files [glob -nocomplain [file join $Temp *]]
    set Move 1
  } else {
    set Files $Temp
    set Move 0
  }
  set NumberOfFiles [llength $Files]
  set Count 1

  set Fetch(Status) "Sorting Images..."

  if { $Sort == {} } {
    set Sort $Fetch(SortFetchedImages)
  }
  
  set Fetch(Progress) 0
  foreach File $Files {
    array unset Tags
    set Answer [GetDicomTags $File [list [list InstanceNumber $Count] {CardiacNumberOfImages -1} {SliceLocation -1} {StudyID 1} {SeriesNumber 1} {Modality Unknown} {StationName Unknown}]]
    if { $Answer == "" } { continue }
    array set Tags $Answer
    
    switch $Sort {
      ExamSeriesImage {
        set Filename [file join $Tags(StudyID) $Tags(SeriesNumber) [format Image%04d.dcm $Tags(InstanceNumber)]]
      }
      ExamSeriesPhaseImage {
        if { $Tags(CardiacNumberOfImages) == -1 } {
          set Filename [file join $Tags(StudyID) $Tags(SeriesNumber) [format Image%04d.dcm $Tags(InstanceNumber)]]
        } else {
          # Log "Instance $Tags(InstanceNumber): [expr $Tags(InstanceNumber) % $Tags(CardiacNumberOfImages)]"
          set D [format Phase%02d [expr $Tags(InstanceNumber) % $Tags(CardiacNumberOfImages)]]
          set Filename [file join $Tags(StudyID) $Tags(SeriesNumber) $D [format Image%04d.dcm $Tags(InstanceNumber)]]
        }
      }
      ExamSeriesLocationImage {
        if { $Tags(SliceLocation) == -1 } {
          set Filename [file join $Tags(StudyID) $Tags(SeriesNumber) [format Image%04d.dcm $Tags(InstanceNumber)]]
        } else {
          # Log "Instance $Tags(InstanceNumber): [expr $Tags(InstanceNumber) % $Tags(CardiacNumberOfImages)]"
          set D "Location$Tags(SliceLocation)"
          set Filename [file join $Tags(StudyID) $Tags(SeriesNumber) $D [format Image%04d.dcm $Tags(InstanceNumber)]]
        }
      }
      ExamStationSeriesImage {
        set Filename [file join "$Tags(StudyID)$Tags(StationName)" $Tags(SeriesNumber) [format Image%04d.dcm $Tags(InstanceNumber)]]
      }
      PatientNameSeriesImage {
        set Filename [file join "$Tags(PatientsName)" $Tags(SeriesNumber) [format Image%04d.dcm $Tags(InstanceNumber)]]
      }
      ExamPatientNameSeriesImage {
        set Filename [file join "$Tags(StudyID) $Tags(PatientsName)" $Tags(SeriesNumber) [format Image%04d.dcm $Tags(InstanceNumber)]]
      }
      PatientIDSeriesImage {
        set Filename [file join "$Tags(PatientID)" $Tags(SeriesNumber) [format Image%04d.dcm $Tags(InstanceNumber)]]
      }
      Image {
        set Filename [file join [format Image%04d.dcm $Tags(InstanceNumber)]]
      }
      ModalityStationExamSeriesImage {
        set Filename [file join $Tags(Modality) $Tags(StationName) $Tags(StudyID) $Tags(SeriesNumber) [format Image%04d.dcm $Tags(InstanceNumber)]]
      }
      ModalityExamSeriesImage {
        set Filename [file join $Tags(Modality) $Tags(StudyID) $Tags(SeriesNumber) [format Image%04d.dcm $Tags(InstanceNumber)]]
      }
      Fancy {
        set map [list ' "" + _ ` _ ~ _ ! _ @ _ \# _ \$ _ % _ ^ _ & _ * _ ( _ ) _ \{ _ \} _ \[ _ \] _ / _ = _ \\ _ | _ < _ > _ , _ . _ " " _]

        set Name [string map $map $Tags(PatientsName)]
        set Date [clock format [clock scan $Tags(StudyDate)] -format "%Y-%m-%d"]
        set Exam "[string toupper $Tags(Modality)]$Tags(StudyID)"
        if { $Tags(AcquisitionNumber) != 0.0 } {
            set Dir [string map $map [format "Series%03d-Acquisition%03d" $Tags(SeriesNumber) $Tags(AcquisitionNumber)]]
        } else {
            set Dir [string map $map [format "Series%03d" $Tags(SeriesNumber)]]
        }
        set F [format Image%04d.dcm $Tags(InstanceNumber)]
        set Filename [file join $Name $Date $Exam $Dir $F]
        # set Link [format "Series%03d" $Tags(SeriesNumber)]
        set Link [string map $map [format "Series%03d_%s" $Tags(SeriesNumber) $Tags(SeriesDescription)]]
        set Link [file join $Name $Date $Exam $Link]
        set Target [file join $Name $Date $Exam $Dir]
      }
    }
    set Filename [file join $Directory $Filename]
    file mkdir [file dir $Filename]
    set Fetch(Status) "Writing $Filename"
    if { $Move } {
      file rename -force -- $File $Filename
    } else {
      file copy -force -- $File $Filename
    }
    if { [info exists Link] } {
      # Don't link, just touch a file...
      set fid [open [file join $Directory $Link] "w"]
      close $fid
      # if { [catch { file link [file join $Directory $Link] [file join $Directory $Target] } Result] } {
	# Log "Link File Failed: $Link $Target\n$Result"
      # }
      unset Link
      unset Target
    }
    set Fetch(Progress) [expr 100 * ($Count / double($NumberOfFiles))]
    incr Count
    update    
  }
  if { $Move } {
    file delete -force $Temp
  }
}

proc HandleStoreSCP { fid } {
    global Fetch

    # Just ignore all output
    if { ![eof $fid] } {
	set Line [gets $fid]
	Log "HandleStoreSCP: $Line"
    }
}

proc HandleMove { fid } {
  global Fetch

  if { ![eof $fid] } {
    set Line [gets $fid]
    Log "$Line"
    if { [string match "*Status=Failed:*" $Line] } {
      catch { regexp {\[([^\]]+)\]} $Line foo Fetch(FetchStatus) }
      Log $Fetch(FetchStatus)
    }
    if { [string match *NumberOfRemainingSubOperations* $Line] } {
      set Fetch(Remaining) [lindex $Line 1]
    }
    if { [string match *NumberOfCompletedSubOperations* $Line] } {
      set Fetch(Completed) [lindex $Line 1]
    }
    if { $Fetch(Completed) + $Fetch(Remaining) != 0 } {
      set Fetch(Progress) [expr 100 * $Fetch(Completed) / ($Fetch(Completed) + $Fetch(Remaining))]
      set Fetch(Status) "Fetching Images from server ($Fetch(Completed)/[expr $Fetch(Remaining) + $Fetch(Completed)]) [$Fetch(Queue) size] job(s) remaining."
    } else { set Fetch(Progress) 0 }
  } else { set Fetch(Done) 1 }
}

if { ![winfo exists .fetch] } { Initialize }

proc WalkDirectory { Queue } \
{
  set Output ""
  
  while { [llength $Queue] != 0 } \
  {
    set Filename [lindex $Queue 0]
    set Queue [lrange $Queue 1 end]

    if { [file isdirectory $Filename] } \
    {
      set Status [catch { set Queue [concat $Queue [glob -nocomplain -- [file join $Filename *]]] } Result]
      continue;
    }
    lappend Output $Filename
  }
  return $Output
}

proc FindDirectories { Queue } \
{
  set Output ""
  
  while { [llength $Queue] != 0 } \
  {
    set Filename [lindex $Queue 0]
    set Queue [lrange $Queue 1 end]

    if { [file isdirectory $Filename] } \
    {
      lappend Output $Filename
      foreach f [glob -nocomplain -- [file join $Filename *]] {
        if { [file isdirectory $f] } {
          lappend Queue $f
        }
      }
    }
  }
  return $Output
}

proc DisplayDicomTags { {Filename {}}  } {
  global Fetch

  if { $Filename == {} } {
    set Filename [tk_getOpenFile -initialdir $Fetch(FetchDirectory) -initialfile $Fetch(CSVFile) -parent .fetch -title "List DICOM Tags" -filetypes [list [list DICOM {.dcm}] [list DICOM {.dicom}] [list {All Files} *]]]
  }
  if { $Filename == {} } { return }
  set Fetch(FetchDirectory) [file dir $Filename]
  set Fetch(DICOMFile) [file tail $Filename]
  SavePreferences
  
  set wid 0
  while { [winfo exists .fetch.tags$wid] } { incr wid }

  set w [toplevel .fetch.tags$wid -width 500 -height 500]
  wm title $w "FetchDICOM - Display Tags $Filename"

  # set Tab [tabcontrol $w.tabs -width auto]

  set List [listcontrol $w.all -selectmode single]
  $List column insert Tag end -text "Tag" -width 200
  $List column insert Value end -text "Value" -width 500

  array set Tags [GetDicomTags $Filename]
  set Tags(Filename) $Filename
  foreach Name [lsort [array names Tags]] {
    set Value $Tags($Name)
    set item [list $Name $Value]
    Log $item
    $List insert end $item
  }

  # set t [$Tab insert all 0 -text "All " -window $Tab.all]
  # pack $Tab -expand 1 -fill both
  pack $w.all -expand 1 -fill both
  wm geometry .fetch $Fetch(WindowGeometry)
  
}

# Find all the "Frame0001.dcm" files in the current directory
proc ContactSheet {} {
  global Fetch
  set Directory [tk_chooseDirectory -initialdir $Fetch(FetchDirectory) -parent .fetch -title "Choose files to sort"]
  if { $Directory == "" } { return }

  ProgressDlg .fetch.pushprogress -parent .fetch -title "Generating Contact Sheet..." \
  -maximum 100 -width 40 -variable Fetch(Progress) -stop {} \
  -textvariable Fetch(Status)
  update
  set Fetch(Status) "Finding images..."
  set Files [WalkDirectory [list $Directory]]
  set Fetch(FetchDirectory) $Directory
  SavePreferences

  set ContactFile [tk_getSaveFile -initialdir $Fetch(FetchDirectory) -initialfile ContactSheet.png -parent .fetch -title "Save Contact Sheet"]
  if { $ContactFile == "" } { return }

  set Directory [file dir $ContactFile]
  set i 0
  # Make a temporary directory
  while { 1 } {
    set TempDir [file join $Directory [format Temp%d $i]]
    if { ![file exists $TempDir] } { break }
    incr i
  }
  file mkdir $TempDir

  set Fetch(Progress) 0
  set Count 1
  set NumberOfFiles [llength $Files]
  foreach File $Files {
    array unset Tags
    set Answer [GetDicomTags $File [list [list InstanceNumber 1] {ImagesInAcquisition 1} {CardiacNumberOfImages -1} {SliceLocation -1} {StudyID 1} {SeriesNumber 1} {Modality Unknown} {StationName Unknown}]]
    if { $Answer == "" } { continue }
    array set Tags $Answer
    if { $Tags(InstanceNumber) == [expr round ( $Tags(ImagesInAcquisition) / 2.0 )] } {
      set Filename "$Tags(StudyID)-$Tags(SeriesNumber).png"

      # Copy and convert
      set Output [file join $TempDir $Filename]
      Log "dcm2pnm -O +Wh 1 +G $File | pnmtopng > $Output"
      if { ![catch {exec dcm2pnm -O +Wh 1 +G $File | pnmtopng > $Output} Result] && ![file exist $Output] } {
        tk_messageBox -parent .fetch -title "Error in dcm2pnm" -message "Error generating png: $Result" -type ok
        break
      }
        
    }
    set Fetch(Progress) [expr 100 * ($Count / double($NumberOfFiles))]
    incr Count
    update    
  }
  # Do the montage
  set Fetch(Status) "Generating Montage"

  set Files [glob $TempDir/*]
  set Files [lsort -dictionary $Files]
  set NumberOfFiles [llength $Files]
  set count 0
  while { [llength $Files] > 0 } {
    set OutputFilename "[file root $ContactFile]$count[file ext $ContactFile]"
    set Fetch(Status) "Writing montage: [file tail $OutputFilename]"
    incr count
    set Status [catch {
      Log "montage -label %f [lrange $Files 0 23] $OutputFilename"
      eval exec montage -label %f [lrange $Files 0 23] $OutputFilename
    } Result]
    if { !$Status && ![file exists $OutputFilename] } {
      tk_messageBox -parent .fetch -title "Error in Montage" -message "Error generating Montage: $Result" -type ok
      break
    }
    set Files [lrange $Files 24 end]
    set Fetch(Progress) [expr ($NumberOfFiles - [llength $Files]) / double($NumberOfFiles) * 100]
    update
  }

  destroy .fetch.pushprogress
}

proc GetDicomTags { Filename {MustExist {}} {SearchList {}} } {
  global Fetch
  # Return an "array get" format of the DICOM tags in the file

  set Command "[DCMTK dcmdump] --load-short [list [file nativename $Filename]]"
  if { $SearchList != {} } {
    set Command "[DCMTK dcmdump] --load-short "
    foreach s $SearchList {
      append Command " --search $s "
    }
    append Command " [list [file nativename $Filename]]"
    Log $Command
  }
  
  set Status [catch { eval exec $Command } Result]
  if { $Status } {
    Log "Returning blank"
    return ""
  }

  foreach Name [list SeriesDescription ScanOptions StudyID SeriesDate SeriesTime] {
    set Tags($Name) ""
  }
  foreach Name [list SeriesNumber AcquisitionNumber EchoTime RepetitionTime FlipAngle] {
    set Tags($Name) 0.0
  }
  
  set T [split $Result "\n"]
  foreach Item $T {
    set Status [regexp {\([^,]+,[^,]+\) [A-Z][A-Z] ([^#]+) #[[:blank:]]+[0-9]+,[\s]+[0-9]+[\s]+(.*)} $Item Foo Value Tag]
    if { $Status == 0 } {
      continue
    }
    set Value [string trim $Value]
    set Value [string trim $Value "\[\]"]
    set Tags($Tag) [string trim $Value]
  }
 foreach Item $MustExist {
   set Tag [lindex $Item 0]
   set Value [lindex $Item 1]
   if { ![info exists Tags($Tag)] } { set Tags($Tag) $Value }
   if { $Tags($Tag) == "(no value available)" } { set Tags($Tag) $Value }
  }
  return [array get Tags]
}


# show the tkconsole for manipulating internal structure and run scripts
proc ShowConsole {} {

  #uplevel #0 source [file join [file dir [info nameofexecutable]] lib/tkcon.tcl]
  # TODO: package for starkit
  # uplevel \#0 source FetchDICOM.vfs/lib/tkcon/tkcon.tcl
  catch { package require tkcon}
  # ::tkcon::Init 
  ::tkcon attach Main
}

      
