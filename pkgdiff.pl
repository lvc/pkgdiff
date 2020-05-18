#!/usr/bin/perl
###########################################################################
# PkgDiff - Package Changes Analyzer 1.8
# A tool for visualizing changes in Linux software packages
#
# Copyright (C) 2012-2018 Andrey Ponomarenko's ABI Laboratory
#
# Written by Andrey Ponomarenko
#
# PLATFORMS
# =========
#  GNU/Linux, FreeBSD, Mac OS X
#
# PACKAGE FORMATS
# ===============
#  RPM, DEB, TAR.GZ, JAR, etc.
#
# REQUIREMENTS
# ============
#  Perl 5 (5.8 or newer)
#  GNU Diff
#  GNU Wdiff
#  GNU Awk
#  GNU Binutils (readelf)
#  Perl-File-LibMagic
#  RPM (rpm, rpmbuild, rpm2cpio) for analysis of RPM-packages
#  DPKG (dpkg, dpkg-deb) for analysis of DEB-packages
#
# SUGGESTIONS
# ===========
#  ABI Compliance Checker (1.99.1 or newer)
#  ABI Dumper (0.97 or newer)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
###########################################################################
use strict;
use Getopt::Long;
Getopt::Long::Configure ("posix_default", "no_ignore_case", "permute");
use File::Path qw(mkpath rmtree);
use File::Temp qw(tempdir);
use File::Copy qw(move copy);
use File::Compare;
use Cwd qw(abs_path cwd);
use Config;
use Fcntl;

my $TOOL_VERSION = "1.8";
my $ORIG_DIR = cwd();

# Internal modules
my $MODULES_DIR = getModules();
push(@INC, getDirname($MODULES_DIR));

my $DIFF = $MODULES_DIR."/Internals/Tools/rfcdiff-1.41-CUSTOM.sh";
my $JAVA_DUMP = $MODULES_DIR."/Internals/Tools/java-dump.sh";
my $ACC = "abi-compliance-checker";
my $ACC_VER = "1.99.1";
my $ABI_DUMPER = "abi-dumper";
my $ABI_DUMPER_VER = "0.97";

my ($Help, $ShowVersion, $DumpVersion, $GenerateTemplate, %Descriptor,
$CheckUsage, $PackageManager, $OutputReportPath, $ShowDetails, $Debug,
$SizeLimit, $QuickMode, $DiffWidth, $DiffLines, $Minimal, $NoWdiff,
$IgnoreSpaceChange, $IgnoreAllSpace, $IgnoreBlankLines, $ExtraInfo,
$CustomTmpDir, $HideUnchanged, $TargetName, $TargetTitle, %TargetVersion,
$CompareDirs, $ListAddedRemoved, $SkipSubArchives, $LinksTarget,
$SkipPattern, $AllText, $CheckByteCode, $FullMethodDiffs, $TrackUnchanged);

my $CmdName = getFilename($0);

my %ERROR_CODE = (
    # Unchanged verdict
    "Unchanged"=>0,
    # Changed verdict
    "Changed"=>1,
    # Undifferentiated error code
    "Error"=>2,
    # System command is not found
    "Not_Found"=>3,
    # Cannot access input files
    "Access_Error"=>4,
    # Cannot find a module
    "Module_Error"=>9
);

my $HomePage = "https://github.com/lvc/pkgdiff";

my $ShortUsage = "Package Changes Analyzer (PkgDiff) $TOOL_VERSION
A tool for visualizing changes in Linux software packages
Copyright (C) 2018 Andrey Ponomarenko's ABI Laboratory
License: GNU GPL

Usage: $CmdName PKG1 PKG2 [options]
Example: $CmdName OLD.rpm NEW.rpm

More info: $CmdName --help\n";

if($#ARGV==-1)
{
    printMsg("INFO", $ShortUsage);
    exit(0);
}

GetOptions("h|help!" => \$Help,
  "v|version!" => \$ShowVersion,
  "dumpversion!" => \$DumpVersion,
# arguments
  "old=s" => \$Descriptor{1},
  "new=s" => \$Descriptor{2},
# options
  "check-usage!" => \$CheckUsage,
  "pkg-manager=s" => \$PackageManager,
  "template!" => \$GenerateTemplate,
  "report-path=s" => \$OutputReportPath,
  "details!" => \$ShowDetails,
  "size-limit=s" => \$SizeLimit,
  "width=s" => \$DiffWidth,
  "prelines=s" => \$DiffLines,
  "ignore-space-change" => \$IgnoreSpaceChange,
  "ignore-all-space" => \$IgnoreAllSpace,
  "ignore-blank-lines" => \$IgnoreBlankLines,
  "quick!" => \$QuickMode,
  "minimal!" => \$Minimal,
  "no-wdiff!" => \$NoWdiff,
  "extra-info=s" => \$ExtraInfo,
  "tmp-dir=s" => \$CustomTmpDir,
  "hide-unchanged!" => \$HideUnchanged,
  "debug!" => \$Debug,
  "v1|vnum1=s" => \$TargetVersion{1},
  "v2|vnum2=s" => \$TargetVersion{2},
  "name=s" => \$TargetName,
  "title=s" => \$TargetTitle,
  "d|directories!" => \$CompareDirs,
  "list-added-removed!" => \$ListAddedRemoved,
  "skip-subarchives!" => \$SkipSubArchives,
  "skip-pattern=s" => \$SkipPattern,
  "all-text!" => \$AllText,
  "links-target=s" => \$LinksTarget,
  "check-byte-code!" => \$CheckByteCode,
  "full-method-diffs!" => \$FullMethodDiffs,
  "track-unchanged!" => \$TrackUnchanged
) or errMsg();

my $TMP_DIR = undef;

if($CustomTmpDir)
{
    printMsg("INFO", "using custom temp directory: $CustomTmpDir");
    $TMP_DIR = abs_path($CustomTmpDir);
    mkpath($TMP_DIR);
    cleanTmp();
}
else {
    $TMP_DIR = tempdir(CLEANUP=>1);
}

sub cleanTmp()
{
    foreach my $E ("null", "error",
    "unpack", "output", "fmt",
    "content1", "content2",
    "xcontent1", "xcontent2")
    {
        if(-f $TMP_DIR."/".$E) {
            unlink($TMP_DIR."/".$E);
        }
        elsif(-d $TMP_DIR."/".$E) {
            rmtree($TMP_DIR."/".$E);
        }
    }
}

if(@ARGV)
{
    if($#ARGV==1)
    { # pkgdiff OLD.pkg NEW.pkg
        $Descriptor{1} = $ARGV[0];
        $Descriptor{2} = $ARGV[1];
    }
    else {
        errMsg();
    }
}

sub errMsg()
{
    printMsg("INFO", "\n".$ShortUsage);
    exit($ERROR_CODE{"Error"});
}

my $HelpMessage="
NAME:
  Package Changes Analyzer
  A tool for visualizing changes in Linux software packages

DESCRIPTION:
  Package Changes Analyzer (PkgDiff) is a tool for visualizing
  changes in Linux software packages (RPM, DEB, TAR.GZ, etc).
  
  The tool can compare directories as well (with the help of
  the -d option).

  The tool is intended for Linux maintainers who are interested
  in ensuring compatibility of old and new versions of packages.

  This tool is free software: you can redistribute it and/or
  modify it under the terms of the GNU GPL.

USAGE:
  $CmdName PKG1 PKG2 [options]
  $CmdName -d DIR1/ DIR2/ [options]

EXAMPLES:
  $CmdName OLD.rpm NEW.rpm
  $CmdName OLD.deb NEW.deb
  $CmdName OLD.tar.gz NEW.tar.gz

ARGUMENTS:
   PKG1
      Path to the old version of a package (RPM, DEB, TAR.GZ, etc).
      
      If you need to analyze a group of packages then you can
      pass an XML-descriptor of this group (VERSION.xml file):

          <version>
            /* Group version */
          </version>

          <group>
            /* Group name */
          </group>
        
          <packages>
            /path1/to/package(s)
            /path2/to/package(s)
            ...
          </packages>

   PKG2
      Path to the new version of a package (RPM, DEB, TAR.GZ, etc).

INFORMATION OPTIONS:
  -h|-help
      Print this help.

  -v|-version
      Print version information.

  -dumpversion
      Print the tool version ($TOOL_VERSION) and don't do anything else.

GENERAL OPTIONS:
  -report-path PATH
      Path to the report.
      Default:
        pkgdiff_reports/<pkg>/<v1>_to_<v2>/changes_report.html

  -details
      Try to create detailed reports.

  -size-limit SIZE
      Don't analyze files larger than SIZE in kilobytes.

  -width WIDTH
      Width of the Visual Diff.
      Default: 80

  -prelines NUM
      Size of the context in the Visual Diff.
      Default: 10

  -ignore-space-change
      Ignore changes in the amount of white space.

  -ignore-all-space
      Ignore all white space.

  -ignore-blank-lines
      Ignore changes whose lines are all blank.

  -quick
      Quick mode without creating of Visual Diffs for files.

  -minimal
      Try to find a smaller set of changes.
  
  -no-wdiff
      Do not use GNU Wdiff for analysis of changes.
      This may be two times faster, but produces lower
      quality reports.

OTHER OPTIONS:
  -check-usage
      Check if package content is used by other
      packages in the repository.

  -pkg-manager NAME
      Specify package management tool.
      Supported:
        urpm - Mandriva URPM

  -template
      Create XML-descriptor template ./VERSION.xml
      
  -extra-info DIR
      Dump extra info to DIR.
      
  -tmp-dir DIR
      Use custom temp directory.
  
  -hide-unchanged
      Don't show unchanged files in the report.

  -debug
      Show debug info.
  
  -name NAME
      Set name of the package to NAME.
  
  -title TITLE
      Set name of the package in the title of the report to TITLE.
  
  -vnum1 NUM
      Set version number of the old package to NUM.
  
  -vnum2 NUM
      Set version number of the new package to NUM.
  
  -links-target TARGET
      Set target attribute for links in the report:
        _self (default)
        _blank
  
  -list-added-removed
      Show content of added and removed text files.
  
  -skip-subarchives
      Skip checking of archives inside the input packages.
  
  -skip-pattern REGEX
      Don't check files matching REGEX.
  
  -d|-directories
      Compare directories instead of packages.
  
  -all-text
      Treat all files in the archive as text files.

  -check-byte-code
      When comparing Java classes, also check for byte code changes.

  -full-method-diffs
      Perform a full diff of method bodies when -check-byte-code is specified.

  -track-unchanged
      Track unchanged files in extra info.

REPORT:
    Report will be generated to:
        pkgdiff_reports/<pkg>/<v1>_to_<v2>/changes_report.html

EXIT CODES:
    0 - Unchanged. The tool has run without any errors.
    non-zero - Changed or the tool has run with errors.

MORE INFORMATION:
    ".$HomePage."\n";

sub helpMsg() {
    printMsg("INFO", $HelpMessage."\n");
}

my $DescriptorTemplate = "
<?xml version=\"1.0\" encoding=\"utf-8\"?>
<descriptor>

/* Primary sections */

<version>
    /* Version of a group of packages */
</version>

<group>
    /* Name of a group of packages */
</group>

<packages>
    /* The list of paths to packages and/or
       directories with packages, one per line */
</packages>

<skip_files>
    /* The list of files that should
       not be analyzed, one per line */
</skip_files>

</descriptor>";

# Settings
my $RENAME_FILE_MATCH = 0.55;
my $RENAME_CONTENT_MATCH = 0.85;
my $MOVE_CONTENT_MATCH = 0.90;
my $MOVE_DEPTH = 4;
my $DEFAULT_WIDTH = 80;
my $DIFF_PRE_LINES = 10;
my $EXACT_DIFF_SIZE = 256*1024;
my $EXACT_DIFF_RATE = 0.1;

my $USE_LIBMAGIC = 0;

my %Group = (
    "Count1"=>0,
    "Count2"=>0
);

my %FormatInfo = ();
my %FileFormat = ();

my %TermFormat = ();
my %DirFormat = ();
my %BytesFormat = ();

# Cache
my %Cache;

# Modes
my $CheckMode = "Single";

# Packages
my %TargetPackages;
my %PackageFiles;
my %PathName;
my %FileChanges;
my %PackageInfo;
my %InfoChanges;
my %PackageUsage;
my %TotalUsage;
my %RemovePrefix;

# Deps
my %PackageDeps;
my %TotalDeps;
my %DepChanges;

# Files
my %AddedFiles;
my %RemovedFiles;
my %ChangedFiles;
my %UnchangedFiles;
my %StableFiles;
my %RenamedFiles;
my %RenamedFiles_R;
my %MovedFiles;
my %MovedFiles_R;
my %ChangeRate;

my %SkipFiles;

# Symbols
my %AddedSymbols;
my %RemovedSymbols;

# Report
my $REPORT_PATH;
my $REPORT_DIR;
my %RESULT;
my $STAT_LINE;

# ABI
my %ABI_Change;

# Other
my %ArchiveFormats = (
    "TAR.GZ"   => ["tar.gz", "tgz",
                   "tar.Z", "taz"],

    "TAR.XZ"   => ["tar.xz", "txz"],

    "TAR.BZ2"  => ["tar.bz2", "tbz2",
                   "tbz", "tb2"],

    "TAR.LZMA" => ["tar.lzma",
                   "tlzma"],

    "TAR.LZ"   => ["tar.lz", "tlz"],

    "ZIP"      => ["zip", "zae"],
    "TAR"      => ["tar"],
    "LZMA"     => ["lzma"],
    "GZ"       => ["gz"],
    "XZ"       => ["xz"],

    "JAR"      => ["jar", "war",
                   "ear", "aar"],
    "APK"      => ["apk"]
);

my $ARCHIVE_EXT = getArchivePattern();

sub getModules()
{
    my $TOOL_DIR = getDirname($0);
    if(not $TOOL_DIR) {
        $TOOL_DIR = ".";
    }
    my @SEARCH_DIRS = (
        # tool's directory
        abs_path($TOOL_DIR),
        # relative path to modules
        abs_path($TOOL_DIR)."/../share/pkgdiff",
        # system directory
        'MODULES_INSTALL_PATH'
    );
    foreach my $DIR (@SEARCH_DIRS)
    {
        if($DIR!~/\A\//)
        { # relative path
            $DIR = abs_path($TOOL_DIR)."/".$DIR;
        }
        if(-d $DIR."/modules") {
            return $DIR."/modules";
        }
    }
    exitStatus("Module_Error", "can't find modules");
}

sub readModule($$)
{
    my ($Module, $Name) = @_;
    my $Path = $MODULES_DIR."/Internals/$Module/".$Name;
    if(not -f $Path) {
        exitStatus("Module_Error", "can't access \'$Path\'");
    }
    return readFile($Path);
}

sub readBytes($)
{ # ELF: 7f454c46
    sysopen(FILE, $_[0], O_RDONLY);
    sysread(FILE, my $Header, 4);
    close(FILE);
    my @Bytes = map { sprintf('%02x', ord($_)) } split (//, $Header);
    return join("", @Bytes);
}

sub readSymbols($)
{
    my $Path = $_[0];
    
    my %Symbols = ();
    
    open(LIB, "readelf -WhlSsdA \"$Path\" 2>\"$TMP_DIR/null\" |");
    my $symtab = undef; # indicates that we are processing 'symtab' section of 'readelf' output
    while(<LIB>)
    {
        if(defined $symtab)
        { # do nothing with symtab
            if(index($_, "'.dynsym'")!=-1)
            { # dynamic table
                $symtab = undef;
            }
        }
        elsif(index($_, "'.symtab'")!=-1)
        { # symbol table
            $symtab = 1;
        }
        elsif(my @Info = readline_ELF($_))
        {
            my ($Bind, $Ndx, $Symbol) = ($Info[3], $Info[5], $Info[6]);
            if($Ndx ne "UND"
            and $Bind ne "WEAK")
            { # only imported symbols
                $Symbols{$Symbol} = 1;
            }
        }
    }
    close(LIB);
    
    return %Symbols;
}

my %ELF_BIND = map {$_=>1} (
    "WEAK",
    "GLOBAL"
);

my %ELF_TYPE = map {$_=>1} (
    "FUNC",
    "IFUNC",
    "OBJECT",
    "COMMON"
);

my %ELF_VIS = map {$_=>1} (
    "DEFAULT",
    "PROTECTED"
);

sub readline_ELF($)
{ # read the line of 'readelf' output corresponding to the symbol
    my @Info = split(/\s+/, $_[0]);
    #  Num:   Value      Size Type   Bind   Vis       Ndx  Name
    #  3629:  000b09c0   32   FUNC   GLOBAL DEFAULT   13   _ZNSt12__basic_fileIcED1Ev@@GLIBCXX_3.4
    shift(@Info); # spaces
    shift(@Info); # num
    if($#Info!=6)
    { # other lines
        return ();
    }
    return () if(not defined $ELF_TYPE{$Info[2]});
    return () if(not defined $ELF_BIND{$Info[3]});
    return () if(not defined $ELF_VIS{$Info[4]});
    if($Info[5] eq "ABS" and $Info[0]=~/\A0+\Z/)
    { # 1272: 00000000     0 OBJECT  GLOBAL DEFAULT  ABS CXXABI_1.3
        return ();
    }
    if(index($Info[2], "0x") == 0)
    { # size == 0x3d158
        $Info[2] = hex($Info[2]);
    }
    return @Info;
}

sub compareSymbols($$)
{
    my ($P1, $P2) = @_;
    
    my %Symbols1 = readSymbols($P1);
    my %Symbols2 = readSymbols($P2);
    
    my $Changed = 0;
    
    foreach my $Symbol (keys(%Symbols1))
    {
        if(not defined $Symbols2{$Symbol})
        {
            $Changed = 1;
            if(defined $AddedSymbols{$Symbol})
            { # moved
                delete($AddedSymbols{$Symbol});
            }
            else
            { # removed
                $RemovedSymbols{$Symbol} = 1;
            }
        }
    }
    
    foreach my $Symbol (keys(%Symbols2))
    {
        if(not defined $Symbols1{$Symbol})
        {
            $Changed = 1;
            if(defined $RemovedSymbols{$Symbol})
            { # moved
                delete($RemovedSymbols{$Symbol})
            }
            else
            { # added
                $AddedSymbols{$Symbol} = 1;
            }
        }
    }
    
    return $Changed;
}

sub compareFiles($$$$)
{
    my ($P1, $P2, $N1, $N2) = @_;
    if(not -f $P1
    or not -f $P2)
    {
        if(not -l $P1)
        { # broken symlinks
            return (0, "", "", 0, {});
        }
    }
    my $Format = getFormat($P1);
    if($Format ne getFormat($P2)) {
        return (0, "", "", 0, {});
    }
    if(getSize($P1) == getSize($P2))
    { # equal size
        if(compare($P1, $P2)==0)
        { # equal content
            return (-1, "", "", 0, {});
        }
    }
    if($QuickMode)
    { # --quick
        return (3, "", "", 1, {});
    }
    if(skipFileCompare($P1, 1))
    { # <skip_files>
        return (2, "", "", 1, {});
    }
    if(defined $SizeLimit)
    {
        if(getSize($P1) > $SizeLimit*1024
        or getSize($P2) > $SizeLimit*1024)
        {
            return (2, "", "", 1, {});
        }
    }
    my ($Changed, $DLink, $RLink, $Rate, $Adv) = (0, "", "", 0, {});
    
    if(not $ShowDetails)
    {
        if($Format eq "SHARED_OBJECT"
        or $Format eq "KERNEL_MODULE"
        or $Format eq "DEBUG_INFO")
        {
            if(not compareSymbols($P1, $P2))
            { # equal sets of symbols
                return (0, "", "", 0, {});
            }
        }
    }
    
    if(defined $FormatInfo{$Format}{"Format"}
    and $FormatInfo{$Format}{"Format"} eq "Text") {
        ($DLink, $Rate) = diffFiles($P1, $P2, getRPath("diffs", $N1));
    }
    elsif($Format eq "LICENSE"
    or $Format eq "CHANGELOG"
    or $Format eq "README"
    or $Format eq "INFORM")
    {
        if($P1=~/\.($ARCHIVE_EXT)\Z/i)
        { # changelog.Debian.gz
            my $Page1 = showFile($P1, "ARCHIVE", 1);
            my $Page2 = showFile($P2, "ARCHIVE", 2);
            ($DLink, $Rate) = diffFiles($Page1, $Page2, getRPath("diffs", $N1));
            
            # clean space
            unlink($Page1);
            unlink($Page2);
        }
        else
        { 
            ($DLink, $Rate) = diffFiles($P1, $P2, getRPath("diffs", $N1));
        }
    }
    elsif($Format eq "SHARED_OBJECT"
    or $Format eq "KERNEL_MODULE"
    or $Format eq "DEBUG_INFO"
    or $Format eq "STATIC_LIBRARY"
    or $Format eq "COMPILED_OBJECT"
    or $Format eq "SHARED_LIBRARY"
    or $Format eq "EXE"
    or $Format eq "MANPAGE"
    or $Format eq "INFODOC"
    or $Format eq "SYMLINK"
    or $Format eq "JAVA_CLASS")
    {
        my $Page1 = showFile($P1, $Format, 1);
        my $Page2 = showFile($P2, $Format, 2);
        if($Format eq "SYMLINK")
        {
            if(readFile($Page1) eq readFile($Page2))
            {
                # clean space
                unlink($Page1);
                unlink($Page2);
                
                return (0, "", "", 0, {});
            }
        }
        ($DLink, $Rate) = diffFiles($Page1, $Page2, getRPath("diffs", $N1));
        
        # clean space
        unlink($Page1);
        unlink($Page2);
    }
    else
    {
        $Changed = 1;
        $Rate = checkDiff($P1, $P2);
    }
    
    if($DLink or $Changed)
    {
        if($ShowDetails)
        { # --details
            if($ACC and $ABI_DUMPER)
            {
                if($Format eq "SHARED_OBJECT"
                or $Format eq "KERNEL_MODULE"
                or $Format eq "DEBUG_INFO"
                or $Format eq "STATIC_LIBRARY") {
                    ($RLink, $Adv) = compareABIs($P1, $P2, $N1, $N2, getRPath("details", $N1));
                }
            }
        }
        $DLink=~s/\A\Q$REPORT_DIR\E\///;
        $RLink=~s/\A\Q$REPORT_DIR\E\///;
        return (1, $DLink, $RLink, $Rate, $Adv);
    }
    
    return (0, "", "", 0, {});
}

sub hexDump($)
{
    my $Path = $_[0];
    my ($Hex, $Byte) = ();
    open(FILE, "<", $Path);
    while(my $Size = read(FILE, $Byte, 16*1024))
    {
        foreach my $Pos (0 .. $Size-1) {
            $Hex .= sprintf('%02x', ord(substr($Byte, $Pos, 1)))."\n";
        }
    }
    close(FILE);
    return $Hex;
}

sub checkDiff($$)
{
    my ($P1, $P2) = @_;
    my $Size1 = getSize($P1);
    if(not $Size1)
    { # empty
        return 1;
    }
    my $Size2 = getSize($P2);
    my $Rate = abs($Size1 - $Size2)/$Size1;
    my $AvgSize = ($Size1 + $Size2)/2;
    if($AvgSize<$EXACT_DIFF_SIZE
    and $Rate<$EXACT_DIFF_RATE)
    {
        my $TmpFile = $TMP_DIR."/null";
        if(-T $P1)
        { # Text
            my $TDiff = $TMP_DIR."/txtdiff";
            qx/diff -Bw \"$P1\" \"$P2\" >$TDiff 2>$TmpFile/;
            $Rate = getRate($P1, $P2, $TDiff);
            unlink($TDiff);
        }
        else
        { # Binary
            my $TDiff = $TMP_DIR."/txtdiff";
            my $T1 = $TMP_DIR."/tmp1.txt";
            my $T2 = $TMP_DIR."/tmp2.txt";
            writeFile($T1, hexDump($P1));
            writeFile($T2, hexDump($P2));
            qx/diff -Bw \"$T1\" \"$T2\" >$TDiff 2>$TmpFile/;
            unlink($T1);
            unlink($T2);
            $Rate = getRate($P1, $P2, $TDiff);
            unlink($TDiff);
        }
    }
    if($Rate>1) {
        $Rate=1;
    }
    return $Rate;
}

sub showFile($$$)
{
    my ($Path, $Format, $Version) = @_;
    my ($Dir, $Name) = sepPath($Path);
    
    my $Cmd = undef;
    
    if($Format eq "MANPAGE")
    {
        $Name=~s/\.(gz|bz2|xz)\Z//;
        $Cmd = "man \"$Path\" 2>&1|col -bfx";
    }
    elsif($Format eq "INFODOC")
    {
        $Name=~s/\.(gz|bz2|xz)\Z//;
        $Path=~s/\.(gz|bz2|xz)\Z//;
        $Cmd = "info \"$Path\"";
    }
    elsif($Format eq "ARCHIVE")
    {
        my $Unpack = $TMP_DIR."/unpack/";
        rmtree($Unpack);
        unpackArchive($Path, $Unpack);
        my @Contents = listDir($Unpack);
        if($#Contents==0) {
            $Cmd = "cat \"$Unpack/".$Contents[0]."\"";
        }
        else {
            return undef;
        }
    }
    elsif($Format eq "SHARED_OBJECT"
    or $Format eq "KERNEL_MODULE"
    or $Format eq "DEBUG_INFO"
    or $Format eq "EXE"
    or $Format eq "COMPILED_OBJECT"
    or $Format eq "STATIC_LIBRARY")
    {
        $Cmd = "readelf -Wa \"$Path\"";
    }
    elsif($Format eq "SHARED_LIBRARY")
    {
        $Cmd = "otool -TVL \"$Path\"";
    }
    elsif($Format eq "SYMLINK")
    {
        $Cmd = "file -b \"$Path\"";
    }
    elsif($Format eq "JAVA_CLASS")
    {
        if(not checkCmd("javap")) {
            return undef;
        }
        $Name=~s/\.class\Z//;
        $Name=~s/\$/./;
        $Path = $Name;
        if ($CheckByteCode) {
            if ($FullMethodDiffs) {
                $Cmd = "$JAVA_DUMP \"$Path\"";
            } else {
                $Cmd = "$JAVA_DUMP -s \"$Path\"";
            }
        } else {
            $Cmd = "javap \"$Path\""; # -c -private -verbose
        }
        chdir($Dir);
    }
    else
    { # error
        return undef;
    }
    
    my $SPath = $TMP_DIR."/fmt/".$Format."/".$Version."/".$Name;
    mkpath(getDirname($SPath));
    
    my $TmpFile = $TMP_DIR."/null";
    qx/$Cmd >"$SPath" 2>$TmpFile/;
    
    if($Format eq "JAVA_CLASS") {
        chdir($ORIG_DIR);
    }
    
    if($Format eq "SHARED_OBJECT"
    or $Format eq "KERNEL_MODULE"
    or $Format eq "DEBUG_INFO"
    or $Format eq "EXE"
    or $Format eq "COMPILED_OBJECT"
    or $Format eq "STATIC_LIBRARY")
    {
        my $Content = readFile($SPath);
        # 00bf608c  00000008 R_386_RELATIVE
        # 00bf608c  00000008 R_386_NONE
        $Content=~s/[0-9a-f]{8}\s+[0-9a-f]{8}\s+R_386_(RELATIVE|NONE)\s*//g;
        # 0000000000210028  0000000000000008 R_X86_64_RELATIVE 0000000000210028
        $Content=~s/[0-9a-f]{16}\s+[0-9a-f]{16}\s+R_X86_64_RELATIVE\s+[0-9a-f]{16}\s*//g;
        # 00be77ec  0001d507 R_386_JUMP_SLOT        00000000   dlclose
        # 0000000000210348  0000001800000007 R_X86_64_JUMP_SLOT     0000000000000000 mq_receive + 0
        $Content=~s/\n([0-9a-f]{8}|[0-9a-f]{16})\s+([0-9a-f]{8}|[0-9a-f]{16}) /\nXXX YYY /g;
        $Content=~s/    [0-9a-f]{16} / ZZZ /g;
        # 563: 00000000     0 FUNC    GLOBAL DEFAULT  UND FT_New_Face
        # 17: 0000000000000000     0 FUNC    GLOBAL DEFAULT  UND sem_trywait@GLIBC_2.2.5 (2)
        $Content=~s/\n\s*\d+:(\s+[0-9a-f]{8}|\s+[0-9a-f]{16})\s+\d+\s+/\nN: XXX W /g;
        $Content=~s/\Q$Dir\E\///g;
        # Build ID: 88a916b3973e1a27b027706385af41c553a94061
        $Content=~s/\s+Build ID: \w+\s+//g;
        writeFile($SPath, uniqStr($Content));
    }
    
    return $SPath;
}

sub uniqStr($)
{
    my $Str = $_[0];
    my ($Prev, $Res) = ("", "");
    foreach my $Line (split(/\n/, $Str))
    {
        if($Line ne $Prev)
        {
            $Prev = $Line;
            $Res .= $Line."\n";
        }
    }
    return $Res;
}

sub getRPath($$)
{
    my ($Prefix, $N) = @_;
    $N=~s/\A\///g;
    my $RelPath = $Prefix."/".$N."-diff.html";
    my $Path = $REPORT_DIR."/".$RelPath;
    return $Path;
}

sub compareABIs($$$$$)
{
    my ($P1, $P2, $N1, $N2, $Path) = @_;
    
    my $Sect = `readelf -S \"$P1\" 2>\"$TMP_DIR/error\"`;
    my $Name = getFilename($P1);
    
    if($Sect!~/\.debug_info/)
    { # No DWARF info
        printMsg("WARNING", "No debug info in ".$Name);
        return ("", {});
    }
    
    mkpath(getDirname($Path));
    my $Adv = {};
    
    $Name=~s/\.debug\Z//;
    printMsg("INFO", "Compare ABIs of ".$Name." (".showNumber(getSize($P1)/1048576)."M) ...");
    
    $N1=~s/\A\///;
    $N2=~s/\A\///;
    
    my $Cmd = undef;
    my $Ret = undef;
    
    my $D1 = $REPORT_DIR."/abi_dumps/".$Group{"V1"}."/".$N1."-ABI.dump";
    my $D2 = $REPORT_DIR."/abi_dumps/".$Group{"V2"}."/".$N2."-ABI.dump";
    
    $Adv->{"ABIDump"}{1} = $D1;
    $Adv->{"ABIDump"}{2} = $D2;
    
    $Adv->{"ABIDump"}{1}=~s/\A\Q$REPORT_DIR\E\///;
    $Adv->{"ABIDump"}{2}=~s/\A\Q$REPORT_DIR\E\///;
    
    $Cmd = $ABI_DUMPER." \"$P1\" -lver \"".$Group{"V1"}."\" -o \"$D1\" -sort";
    if($Debug)
    {
        $Cmd .= " -extra-info \"$TMP_DIR/extra-info\"";
        printMsg("INFO", "Running $Cmd");
    }
    system($Cmd." >\"$TMP_DIR/output\"");
    $Ret = $?>>8;
    if($Ret!=0)
    { # error
        printMsg("ERROR", "Failed to run ABI Dumper ($Ret)");
        return ("", {});
    }
    
    if($Debug)
    {
        my $DP = $REPORT_DIR."/dwarf_dumps/".$Group{"V1"}."/".$N1."-DWARF.dump";
        mkpath(getDirname($DP));
        move("$TMP_DIR/extra-info/debug_info", $DP);
        
        $Adv->{"DWARFDump"}{1} = $DP;
        $Adv->{"DWARFDump"}{1}=~s/\A\Q$REPORT_DIR\E\///;
    }
    
    $Cmd = $ABI_DUMPER." \"$P2\" -lver \"".$Group{"V2"}."\" -o \"$D2\" -sort";
    if($Debug)
    {
        $Cmd .= " -extra-info \"$TMP_DIR/extra-info\"";
        printMsg("INFO", "Running $Cmd");
    }
    system($Cmd." >\"$TMP_DIR/output\"");
    $Ret = $?>>8;
    if($Ret!=0)
    { # error
        printMsg("ERROR", "Failed to run ABI Dumper ($Ret)");
        return ("", {});
    }
    
    if($Debug)
    {
        my $DP = $REPORT_DIR."/dwarf_dumps/".$Group{"V2"}."/".$N2."-DWARF.dump";
        mkpath(getDirname($DP));
        move("$TMP_DIR/extra-info/debug_info", $DP);
        
        $Adv->{"DWARFDump"}{2} = $DP;
        $Adv->{"DWARFDump"}{2}=~s/\A\Q$REPORT_DIR\E\///;
    }
    
    # clean space
    rmtree("$TMP_DIR/extra-info");
    
    $Cmd = $ACC." -d1 \"$D1\" -d2 \"$D2\"";
    
    $Cmd .= " -l \"".$Name."\"";
    
    $Cmd .= " --report-path=\"$Path\"";
    $Cmd .= " -quiet";
    
    if($Debug) {
        printMsg("INFO", "Running $Cmd");
    }
    system($Cmd);
    $Ret = $?>>8;
    if($Ret!=0 and $Ret!=1)
    { # error
        printMsg("ERROR", "Failed to run ABI Compliance Checker ($Ret)");
        return ("", {});
    }
    
    my ($Bin, $Src) = (0, 0);
    if(my $Meta = readFilePart($Path, 2))
    {
        my @Info = split(/\n/, $Meta);
        if($Info[0]=~/affected:([\d\.]+)/) {
            $Bin = $1;
        }
        if($Info[1]=~/affected:([\d\.]+)/) {
            $Src = $1;
        }
    }
    
    $ABI_Change{"Bin"} += $Bin;
    $ABI_Change{"Src"} += $Src;
    $ABI_Change{"Total"} += 1;
    
    return ($Path, $Adv);
}

sub checkModule($)
{
    foreach my $P (@INC)
    {
        if(-e $P."/".$_[0])
        {
            return 1;
        }
    }
    
    return 0;
}

sub getSize($)
{
    my $Path = $_[0];
    if(not $Path) {
        return 0;
    }
    if($Cache{"getSize"}{$Path}) {
        return $Cache{"getSize"}{$Path};
    }
    if(-l $Path)
    { # symlinks
        return ($Cache{"getSize"}{$Path} = length(getType($Path)));
    }
    return ($Cache{"getSize"}{$Path} = -s $Path);
}

sub diffFiles($$$)
{
    my ($P1, $P2, $Path) = @_;
    
    if(not $P1 or not $P2) {
        return ();
    }
    
    mkpath(getDirname($Path));
    
    my $TmpPath = $TMP_DIR."/diff";
    unlink($TmpPath);
    
    my $Cmd = "sh $DIFF --width $DiffWidth --stdout";
    $Cmd .= " --tmpdiff \"$TmpPath\" --prelines $DiffLines";
    
    if($IgnoreSpaceChange) {
        $Cmd .= " --ignore-space-change";
    }
    if($IgnoreAllSpace) {
        $Cmd .= " --ignore-all-space";
    }
    if($IgnoreBlankLines) {
        $Cmd .= " --ignore-blank-lines";
    }
    if($Minimal)
    { # diff --minimal
        $Cmd .= " --minimal";
    }
    if($NoWdiff) {
        $Cmd .= " --nowdiff";
    }
    
    $Cmd .= " \"".$P1."\" \"".$P2."\" >\"".$Path."\" 2>$TMP_DIR/null";
    $Cmd=~s/\$/\\\$/g;
    
    qx/$Cmd/;
    
    if(getSize($Path)<3500)
    { # may be identical
        if(readFilePart($Path, 2)=~/The files are identical/i)
        {
            unlink($Path);
            return ();
        }
    }
    
    if(getSize($Path)<3100)
    { # may be identical or non-text
        if(index(readFile($Path), "No changes")!=-1)
        {
            unlink($Path);
            return ();
        }
    }
    
    my $Rate = getRate($P1, $P2, $TmpPath);
    
    # clean space
    unlink($TmpPath);
    
    return ($Path, $Rate);
}

sub getRate($$$)
{
    my ($P1, $P2, $PatchPath) = @_;
    
    my $Size1 = getSize($P1);
    if(not $Size1) {
        return 1;
    }
    
    my $Size2 = getSize($P2);
    
    my $Rate = 1;
    # count removed/changed bytes
    my $Patch = readFile($PatchPath);
    $Patch=~s/(\A|\n)([^\-]|[\+]{3}|[\-]{3}).*//g;
    $Rate = length($Patch);
    # count added bytes
    if($Size2>$Size1) {
        $Rate += $Size2-$Size1;
    }
    $Rate /= $Size1;
    if($Rate>1) {
        $Rate=1;
    }
    return $Rate;
}

sub readFilePart($$)
{
    my ($Path, $Num) = @_;
    
    open (FILE, $Path);
    my $Lines = "";
    foreach (1 ... $Num) {
        $Lines .= <FILE>;
    }
    close(FILE);
    
    return $Lines;
}

sub getType($)
{
    my $Path = $_[0];
    
    if($Cache{"getType"}{$Path}) {
        return $Cache{"getType"}{$Path};
    }
    
    if($USE_LIBMAGIC)
    {
        my $Magic = File::LibMagic->new();
        return ($Cache{"getType"}{$Path} = $Magic->describe_filename($Path));
    }
    
    return ($Cache{"getType"}{$Path} = qx/file -b \"$Path\"/);
}

sub isRenamed($$$)
{
    my ($P1, $P2, $Match) = @_;
    my ($D1, $N1) = sepPath($P1);
    my ($D2, $N2) = sepPath($P2);
    if($D1 ne $D2) {
        return 0;
    }
    if($N1 eq $N2) {
        return 0;
    }
    my $L1 = length($N1);
    my $L2 = length($N2);
    if($L1<=8)
    { # too short names
        if($N1=~/\.(\w+)\Z/)
        { # with equal extensions
            my $E = $1;
            if($N2=~s/\.\Q$E\E\Z//g)
            { # compare without extensions
                $N1=~s/\.\Q$E\E\Z//g;
            }
        }
    }
    $Match/=$RENAME_FILE_MATCH;
    my $HL = ($L1+$L2)/$Match;
    return (getBaseLen($N1, $N2)>=$HL);
}

sub minNum($$)
{
    if($_[0]<$_[1]) {
        return $_[0];
    }
    
    return $_[1];
}

sub getDepth($) {
    return ($_[0]=~tr![\/]!!);
}

sub getBaseLen($$)
{
    my ($Str1, $Str2) = @_;
    
    if(defined $Cache{"getBaseLen"}{$Str1}{$Str2}) {
        return $Cache{"getBaseLen"}{$Str1}{$Str2};
    }
    
    if($Str1 eq $Str2) {
        return length($Str1);
    }
    
    my $BLen = 0;
    my $Len1 = length($Str1);
    my $Len2 = length($Str2);
    my $Min = minNum($Len1, $Len2) - 1;
    
    foreach my $Pos (0 .. $Min)
    {
        my $S1 = substr($Str1, $Pos, 1);
        my $S2 = substr($Str2, $Pos, 1);
        if($S1 eq $S2) {
            $BLen+=1;
        }
        else {
            last;
        }
    }
    
    foreach my $Pos (0 .. $Min)
    {
        my $S1 = substr($Str1, $Len1-$Pos-1, 1);
        my $S2 = substr($Str2, $Len2-$Pos-1, 1);
        if($S1 eq $S2) {
            $BLen+=1;
        }
        else {
            last;
        }
    }
    
    return ($Cache{"getBaseLen"}{$Str1}{$Str2}=$BLen);
}

sub isMoved($$)
{
    my ($P1, $P2) = @_;
    my ($D1, $N1) = sepPath($P1);
    my ($D2, $N2) = sepPath($P2);
    if($N1 eq $N2
    and $D1 ne $D2) {
        return 1;
    }
    return 0;
}

sub writeExtraInfo()
{
    my $FILES = "";
    
    $FILES .= "<rate>\n    ".$RESULT{"affected"}."\n</rate>\n\n";
    
    if(my @Added = sort {lc($a) cmp lc($b)} keys(%AddedFiles)) {
        $FILES .= "<added>\n    ".join("\n    ", @Added)."\n</added>\n\n";
    }
    if(my @Removed = sort {lc($a) cmp lc($b)} keys(%RemovedFiles)) {
        $FILES .= "<removed>\n    ".join("\n    ", @Removed)."\n</removed>\n\n";
    }
    if(my @Moved = sort {lc($a) cmp lc($b)} keys(%MovedFiles))
    {
        $FILES .= "<moved>\n";
        foreach (@Moved) {
            $FILES .= "    ".$_.";".$MovedFiles{$_}." (".showNumber($ChangeRate{$_}*100)."%)\n";
        }
        $FILES .= "</moved>\n\n";
    }
    if(my @Renamed = sort {lc($a) cmp lc($b)} keys(%RenamedFiles))
    {
        $FILES .= "<renamed>\n";
        foreach (@Renamed) {
            $FILES .= "    ".$_.";".$RenamedFiles{$_}." (".showNumber($ChangeRate{$_}*100)."%)\n";
        }
        $FILES .= "</renamed>\n\n";
    }
    if(my @Changed = sort {lc($a) cmp lc($b)} keys(%ChangedFiles))
    {
        foreach (0 .. $#Changed) {
            $Changed[$_] .= " (".showNumber($ChangeRate{$Changed[$_]}*100)."%)";
        }
        
        $FILES .= "<changed>\n    ".join("\n    ", @Changed)."\n</changed>\n\n";
    }
    if ($TrackUnchanged) {
        if(my @Unchanged = sort {lc($a) cmp lc($b)} keys(%UnchangedFiles))
        {
            $FILES .= "<unchanged>\n    ".join("\n    ", @Unchanged)."\n</unchanged>\n\n";
        }
    }
    writeFile($ExtraInfo."/files.xml", $FILES);
    
    my $SYMBOLS = "";
    if(my @AddedSymbols = sort {lc($a) cmp lc($b)} keys(%AddedSymbols)) {
        $SYMBOLS .= "<added>\n    ".join("\n    ", @AddedSymbols)."\n</added>\n\n";
    }
    if(my @RemovedSymbols = sort {lc($a) cmp lc($b)} keys(%RemovedSymbols)) {
        $SYMBOLS .= "<removed>\n    ".join("\n    ", @RemovedSymbols)."\n</removed>\n\n";
    }
    writeFile($ExtraInfo."/symbols.xml", $SYMBOLS);
}

sub skipFile($)
{
    my $Name = $_[0];
    
    if(defined $SkipPattern)
    {
        if($Name=~/($SkipPattern)/)
        {
            printMsg("INFO", "skipping (pattern match) ".$Name);
            return 1;
        }
    }
    
    return 0;
}

sub detectChanges()
{
    foreach my $E ("info-diffs", "diffs", "details") {
        mkpath($REPORT_DIR."/".$E);
    }
    
    foreach my $Format (keys(%FormatInfo))
    {
        %{$FileChanges{$Format}} = (
            "Total"=>0,
            "Added"=>0,
            "Removed"=>0,
            "Changed"=>0,
            "Size"=>0,
            "SizeDelta"=>0
        );
    }
    
    my (%AddedByDir, %RemovedByDir, %AddedByName,
    %RemovedByName, %AddedByPrefix, %RemovedByPrefix) = ();
    
    foreach my $Name (sort keys(%{$PackageFiles{1}}))
    { # checking old files
        my $Format = getFormat($PackageFiles{1}{$Name});
        if(not defined $PackageFiles{2}{$Name})
        { # removed files
            $RemovedFiles{$Name} = 1;
            $RemovedByDir{getDirname($Name)}{$Name} = 1;
            $RemovedByName{getFilename($Name)}{$Name} = 1;
            foreach (getPrefixes($Name, $MOVE_DEPTH)) {
                $RemovedByPrefix{$_}{$Name} = 1;
            }
        }
        else {
            $StableFiles{$Name} = 1;
        }
    }
    
    foreach my $Name (keys(%{$PackageFiles{2}}))
    { # checking new files
        my $Format = getFormat($PackageFiles{2}{$Name});
        if(not defined $PackageFiles{1}{$Name})
        { # added files
            $AddedFiles{$Name} = 1;
            $AddedByDir{getDirname($Name)}{$Name} = 1;
            $AddedByName{getFilename($Name)}{$Name} = 1;
            foreach (getPrefixes($Name, $MOVE_DEPTH)) {
                $AddedByPrefix{$_}{$Name} = 1;
            }
        }
    }
    
    foreach my $Name (sort keys(%RemovedFiles))
    { # checking removed files
        my $Path = $PackageFiles{1}{$Name};
        my $Format = getFormat($Path);
        $FileChanges{$Format}{"Total"} += 1;
        $FileChanges{$Format}{"Removed"} += 1;
        if(my $Size = getSize($Path))
        {
            $FileChanges{$Format}{"SizeDelta"} += $Size;
            $FileChanges{$Format}{"Size"} += $Size;
        }
        $FileChanges{$Format}{"Details"}{$Name}{"Status"} = "removed";
    }
    
    foreach my $Name (sort {getDepth($b)<=>getDepth($a)} sort keys(%RemovedFiles))
    { # checking moved files
        my $Format = getFormat($PackageFiles{1}{$Name});
        
        my $FileName = getFilename($Name);
        my @Removed = keys(%{$RemovedByName{$FileName}});
        my @Added = keys(%{$AddedByName{$FileName}});
        
        my @Removed = grep {not defined $MovedFiles{$_}} @Removed;
        my @Added = grep {not defined $MovedFiles_R{$_}} @Added;
        
        if($#Added!=0 or $#Removed!=0)
        {
            my $Found = 0;
            foreach my $Prefix (getPrefixes($Name, $MOVE_DEPTH))
            {
                my @RemovedPrefix = keys(%{$RemovedByPrefix{$Prefix}});
                my @AddedPrefix = keys(%{$AddedByPrefix{$Prefix}});
                
                my @RemovedPrefix = grep {not defined $MovedFiles{$_}} @RemovedPrefix;
                my @AddedPrefix = grep {not defined $MovedFiles_R{$_}} @AddedPrefix;
                
                if($#AddedPrefix==0 and $#RemovedPrefix==0)
                {
                    @Added = @AddedPrefix;
                    $Found = 1;
                }
                
            }
            if(not $Found) {
                next;
            }
        }
        
        foreach my $File (@Added)
        {
            if($Format ne getFormat($PackageFiles{2}{$File}))
            { # different formats
                next;
            }
            if(defined $MovedFiles_R{$File}) {
                next;
            }
            if(isMoved($Name, $File))
            {
                $MovedFiles{$Name} = $File;
                $MovedFiles_R{$File} = $Name;
                last;
            }
        }
    }
    
    foreach my $Name (sort keys(%RemovedFiles))
    { # checking renamed files
        if(defined $MovedFiles{$Name})
        { # moved
            next;
        }
        my $Format = getFormat($PackageFiles{1}{$Name});
        my @Removed = keys(%{$RemovedByDir{getDirname($Name)}});
        my @Added = keys(%{$AddedByDir{getDirname($Name)}});
        my $Match = 2;
        if($#Removed==0 and $#Added==0) {
            $Match *= 2;
        }
        my $FName = getFilename($Name);
        my $Len = length($FName);
        foreach my $File (sort {getBaseLen($FName, getFilename($b)) <=> getBaseLen($FName, getFilename($a))}
        sort { abs(length(getFilename($a))-$Len) <=> abs(length(getFilename($b))-$Len) } @Added)
        {
            if($Format ne getFormat($PackageFiles{2}{$File}))
            { # different formats
                next;
            }
            if(defined $RenamedFiles_R{$File}
            or defined $MovedFiles_R{$File})
            { # renamed or moved
                next;
            }
            if(isRenamed($Name, $File, $Match))
            {
                $RenamedFiles{$Name} = $File;
                $RenamedFiles_R{$File} = $Name;
                last;
            }
        }
    }
    
    foreach my $Name (sort (keys(%StableFiles), keys(%RenamedFiles), keys(%MovedFiles)))
    { # checking files
        my $Path = $PackageFiles{1}{$Name};
        my $Size = getSize($Path);
        if($Debug) {
            printMsg("INFO", $Name);
        }
        my ($NewPath, $NewName) = ($PackageFiles{2}{$Name}, $Name);
        my $Format = getFormat($Path);
        if($StableFiles{$Name})
        { # stable files
            $FileChanges{$Format}{"Total"} += 1;
            $FileChanges{$Format}{"Size"} += $Size;
        }
        elsif($NewName = $RenamedFiles{$Name})
        { # renamed files
            $NewPath = $PackageFiles{2}{$NewName};
        }
        elsif($NewName = $MovedFiles{$Name})
        { # moved files
            $NewPath = $PackageFiles{2}{$NewName};
        }
        
        my ($Changed, $DLink, $RLink, $Rate, $Adv) = compareFiles($Path, $NewPath, $Name, $NewName);
        my %Details = %{$Adv};
        
        if($Changed==1 or $Changed==3)
        {
            if($NewName eq $Name)
            { # renamed and moved files should
              # not be shown in the summary
                $FileChanges{$Format}{"Changed"} += 1;
                $FileChanges{$Format}{"Rate"} += $Rate;
                $FileChanges{$Format}{"SizeDelta"} += $Size*$Rate;
            }
            $Details{"Status"} = "changed";
            if($Changed==1)
            {
                $Details{"Rate"} = $Rate;
                $Details{"Diff"} = $DLink;
                $Details{"Report"} = $RLink;
                $ChangeRate{$Name} = $Rate;
            }
            
            $ChangedFiles{$Name} = 1;
        }
        elsif($Changed==2)
        {
            $Details{"Status"} = "changed";
            $Details{"Skipped"} = 1;
        }
        elsif($Changed==-1)
        {
            $Details{"Status"} = "unchanged";
            $Details{"Empty"} = 1;
            $Details{"Rate"} = 0;
            $UnchangedFiles{$Name} = 1;
        }
        else
        {
            $Details{"Status"} = "unchanged";
            $Details{"Rate"} = 0;
            $UnchangedFiles{$Name} = 1;
        }
        if($NewName = $RenamedFiles{$Name})
        { # renamed files
            if($Rate<$RENAME_CONTENT_MATCH) {
                $Details{"Status"} = "renamed";
            }
            else
            {
                %Details = (
                    "Status"=>"removed"
                );
                delete($RenamedFiles_R{$RenamedFiles{$Name}});
                delete($RenamedFiles{$Name});
                delete($ChangedFiles{$Name});
                unlink($REPORT_DIR."/".$DLink);
            }
        }
        elsif($NewName = $MovedFiles{$Name})
        { # moved files
            if($Rate<$MOVE_CONTENT_MATCH) {
                $Details{"Status"} = "moved";
            }
            else
            {
                %Details = (
                    "Status"=>"removed"
                );
                delete($MovedFiles_R{$MovedFiles{$Name}});
                delete($MovedFiles{$Name});
                delete($ChangedFiles{$Name});
                unlink($REPORT_DIR."/".$DLink);
            }
        }
        %{$FileChanges{$Format}{"Details"}{$Name}} = %Details;
    }
    
    foreach my $Name (keys(%AddedFiles))
    { # checking added files
        my $Path = $PackageFiles{2}{$Name};
        my $Format = getFormat($Path);
        $FileChanges{$Format}{"Total"} += 1;
        $FileChanges{$Format}{"Added"} += 1;
        if(my $Size = getSize($Path))
        {
            $FileChanges{$Format}{"SizeDelta"} += $Size;
            $FileChanges{$Format}{"Size"} += $Size;
        }
        $FileChanges{$Format}{"Details"}{$Name}{"Status"} = "added";
    }

    # Deps
    foreach my $Kind (keys(%{$PackageDeps{1}}))
    { # removed/changed deps
        %{$DepChanges{$Kind}} = (
            "Added"=>0,
            "Removed"=>0,
            "Changed"=>0,
            "Total"=>0,
            "Size"=>0,
            "SizeDelta"=>0
        );
        
        foreach my $Name (keys(%{$PackageDeps{1}{$Kind}}))
        {
            my $Size = length($Name);
            $DepChanges{$Kind}{"Total"} += 1;
            $DepChanges{$Kind}{"Size"} += $Size;
            
            if(not defined($PackageDeps{2}{$Kind})
            or not defined($PackageDeps{2}{$Kind}{$Name}))
            { # removed deps
                $DepChanges{$Kind}{"Details"}{$Name}{"Status"} = "removed";
                $DepChanges{$Kind}{"Removed"} += 1;
                $DepChanges{$Kind}{"SizeDelta"} += $Size;
                next;
            }
            
            my %Info1 = %{$PackageDeps{1}{$Kind}{$Name}};
            my %Info2 = %{$PackageDeps{2}{$Kind}{$Name}};
            if($Info1{"Op"} and $Info1{"V"}
            and ($Info1{"Op"} ne $Info2{"Op"} or $Info1{"V"} ne $Info2{"V"}))
            {
                $DepChanges{$Kind}{"Details"}{$Name}{"Status"} = "changed";
                $DepChanges{$Kind}{"Changed"} += 1;
                $DepChanges{$Kind}{"SizeDelta"} += $Size;
            }
            else {
                $DepChanges{$Kind}{"Details"}{$Name}{"Status"} = "unchanged";
            }
        }
    }
    
    foreach my $Kind (keys(%{$PackageDeps{2}}))
    { # added deps
        foreach my $Name (keys(%{$PackageDeps{2}{$Kind}}))
        {
            if(not defined($PackageDeps{1}{$Kind})
            or not defined($PackageDeps{1}{$Kind}{$Name}))
            {
                $DepChanges{$Kind}{"Total"} += 1;
                $DepChanges{$Kind}{"Details"}{$Name}{"Status"} = "added";
                $DepChanges{$Kind}{"Added"} += 1;
                if(my $Size = length($Name))
                {
                    $DepChanges{$Kind}{"Size"} += $Size;
                    $DepChanges{$Kind}{"SizeDelta"} += $Size;
                }
            }
        }
    }
    
    # Info
    %InfoChanges = (
        "Added"=>0,
        "Removed"=>0,
        "Changed"=>0,
        "Total"=>0,
        "Size"=>0,
        "SizeDelta"=>0
    );
    
    my $OldPkgs = keys(%{$TargetPackages{1}});
    my $NewPkgs = keys(%{$TargetPackages{2}});
    
    if(keys(%PackageInfo)==2
    and $OldPkgs==1
    and $NewPkgs==1)
    { # renamed?
        my @Names = keys(%PackageInfo);
        my $N1 = $Names[0];
        my $N2 = $Names[1];
        
        if(defined $PackageInfo{$N1}{"V2"})
        {
            $PackageInfo{$N2}{"V2"} = $PackageInfo{$N1}{"V2"};
            delete($PackageInfo{$N1});
        }
        elsif(defined $PackageInfo{$N2}{"V2"})
        {
            $PackageInfo{$N1}{"V2"} = $PackageInfo{$N2}{"V2"};
            delete($PackageInfo{$N2});
        }
    }
    
    foreach my $Package (sort keys(%PackageInfo))
    {
        my $Old = $PackageInfo{$Package}{"V1"};
        my $New = $PackageInfo{$Package}{"V2"};
        
        my $OldSize = length($Old);
        my $NewSize = length($New);
        
        $InfoChanges{"Total"} += 1;
        if($Old and not $New)
        {
            $InfoChanges{"Details"}{$Package}{"Status"} = "removed";
            $InfoChanges{"Removed"} += 1;
            $InfoChanges{"Size"} += $OldSize;
            $InfoChanges{"SizeDelta"} += $OldSize;
        }
        elsif(not $Old and $New)
        {
            $InfoChanges{"Details"}{$Package}{"Status"} = "added";
            $InfoChanges{"Added"} += 1;
            $InfoChanges{"Size"} += $NewSize;
            $InfoChanges{"SizeDelta"} += $NewSize;
        }
        elsif($Old ne $New)
        {
            my $P1 = $TMP_DIR."/1/".$Package."-info";
            my $P2 = $TMP_DIR."/2/".$Package."-info";
            
            writeFile($P1, $Old);
            writeFile($P2, $New);
            
            my ($DLink, $Rate) = diffFiles($P1, $P2, getRPath("info-diffs", $Package."-info"));
            
            # clean space
            rmtree($TMP_DIR."/1/");
            rmtree($TMP_DIR."/2/");
            
            $DLink =~s/\A\Q$REPORT_DIR\E\///;
            
            my %Details = ();
            $Details{"Status"} = "changed";
            $Details{"Rate"} = $Rate;
            $Details{"Diff"} = $DLink;
            
            %{$InfoChanges{"Details"}{$Package}} = %Details;
            $InfoChanges{"Changed"} += 1;
            $InfoChanges{"Rate"} += $Rate;
            $InfoChanges{"Size"} += $OldSize;
            $InfoChanges{"SizeDelta"} += $OldSize*$Rate;
        }
        else
        {
            $InfoChanges{"Details"}{$Package}{"Status"} = "unchanged";
            $InfoChanges{"Size"} += $OldSize;
            $InfoChanges{"SizeDelta"} += $OldSize;
        }
    }
    
    $STAT_LINE .= "added:".keys(%AddedFiles).";";
    $STAT_LINE .= "removed:".keys(%RemovedFiles).";";
    $STAT_LINE .= "moved:".keys(%MovedFiles).";";
    $STAT_LINE .= "renamed:".keys(%RenamedFiles).";";
    $STAT_LINE .= "changed:".keys(%ChangedFiles).";";
    $STAT_LINE .= "unchanged:".keys(%UnchangedFiles).";";
}

sub htmlSpecChars($)
{
    my $Str = $_[0];
    $Str=~s/\&([^#])/&amp;$1/g;
    $Str=~s/</&lt;/g;
    $Str=~s/>/&gt;/g;
    $Str=~s/\"/&quot;/g;
    $Str=~s/\'/&#39;/g;
    return $Str;
}

sub getReportUsage()
{
    if(not keys(%PackageUsage)) {
        return "";
    }
    
    my $Report = "<a name='Usage'></a>\n";
    $Report .= "<h2>Usage Analysis</h2><hr/>\n";
    $Report .= "<table class='summary highlight'>\n";
    $Report .= "<tr><th>Package</th><th>Status</th><th>Used By</th></tr>\n";
    
    foreach my $Package (sort keys(%PackageUsage))
    {
        my $Num = keys(%{$PackageUsage{$Package}{"UsedBy"}});
        $Report .= "<tr>\n";
        $Report .= "<td class='left f_path'>$Package</td>\n";
        if($Num)
        {
            $Report .= "<td class='warning'>used</td>\n";
            if($Num==1) {
                $Report .= "<td>$Num package</td>\n";
            }
            else {
                $Report .= "<td>$Num packages</td>\n";
            }
        }
        else
        {
            $Report .= "<td class='passed'>unused</td>\n";
            $Report .= "<td></td>\n";
        }
        
        $Report .= "</tr>\n";
    }
    $Report .= "</table>\n";
    
    return $Report;
}

sub getReportHeaders()
{
    if(not keys(%PackageInfo)) {
        return "";
    }
    
    my $Report = "<a name='Info'></a>\n";
    $Report .= "<h2>Changes In Package Info</h2><hr/>\n";
    $Report .= "<table class='summary highlight'>\n";
    $Report .= "<tr><th>Package</th><th>Status</th><th>Delta</th><th>Visual Diff</th></tr>\n";
    
    my %Details = %{$InfoChanges{"Details"}};
    foreach my $Package (sort keys(%Details))
    {
        my $Status = $Details{$Package}{"Status"};
        $Report .= "<tr>\n";
        if($Status eq "removed")
        {
            $Report .= "<td class='left f_path failed'>$Package</td>\n";
            $Report .= "<td class='failed'>removed</td><td></td><td></td>\n";
        }
        elsif($Status eq "added")
        {
            $Report .= "<td class='left f_path new'>$Package</td>\n";
            $Report .= "<td class='new'>added</td><td></td><td></td>\n";
        }
        else
        {
            $Report .= "<td class='left f_path'>$Package</td>\n";
            if($Status eq "changed")
            {
                $Report .= "<td class='warning'>changed</td>\n";
                $Report .= "<td class='value'>".showNumber($Details{$Package}{"Rate"}*100)."%</td>\n";
                $Report .= "<td><a href='".encodeUrl($Details{$Package}{"Diff"})."' target=\'$LinksTarget\'>diff</a></td>\n";
            }
            else
            {
                $Report .= "<td class='passed'>unchanged</td>\n";
                $Report .= "<td>0%</td><td></td>\n";
            }
        }
        $Report .= "</tr>\n";
    }
    $Report .= "</table>\n";
    
    return $Report;
}

sub getReportDeps()
{
    my $Report = "<a name='Deps'></a>\n";
    foreach my $Kind (sort keys(%DepChanges))
    {
        my @Names = keys(%{$DepChanges{$Kind}{"Details"}});
        if(not @Names) {
            next;
        }
        $Report .= "<h2>Changes In \"".ucfirst($Kind)."\" Dependencies</h2><hr/>\n";
        $Report .= "<table class='summary highlight'>\n";
        $Report .= "<tr><th>Name</th><th>Status</th><th>Old<br/>Version</th><th>New<br/>Version</th></tr>\n";
        foreach my $Name (sort {lc($a) cmp lc($b)} @Names)
        {
            my $Status = $DepChanges{$Kind}{"Details"}{$Name}{"Status"};
            my $Color = "";
            if($Status eq "removed") {
                $Color = " failed";
            }
            elsif($Status eq "added") {
                $Color = " new";
            }
            $Report .= "<tr>\n";
            $Report .= "<td class='left f_path$Color\'>$Name</td>\n";
            if($Status eq "changed") {
                $Report .= "<td class='warning'>".$Status."</td>\n";
            }
            elsif($Status eq "removed") {
                $Report .= "<td class='failed'>".$Status."</td>\n";
            }
            elsif($Status eq "added") {
                $Report .= "<td class='new'>".$Status."</td>\n";
            }
            else {
                $Report .= "<td class='passed'>".$Status."</td>\n";
            }
            if($PackageDeps{1}{$Kind}{$Name})
            {
                my %Info1 = %{$PackageDeps{1}{$Kind}{$Name}};
                $Report .= "<td class='value'>".htmlSpecChars(showOp($Info1{"Op"}).$Info1{"V"})."</td>\n";
            }
            else {
                $Report .= "<td></td>\n";
            }
            if($PackageDeps{2}{$Kind}{$Name})
            {
                my %Info2 = %{$PackageDeps{2}{$Kind}{$Name}};
                $Report .= "<td class='value'>".htmlSpecChars(showOp($Info2{"Op"}).$Info2{"V"})."</td>\n";
            }
            else {
                $Report .= "<td></td>\n";
            }
            $Report .= "</tr>\n";
        }
        $Report .= "</table>\n";
    }
    return $Report;
}

sub showOp($)
{
    my $Op = $_[0];
    #$Op=~s/<=/&le;/g;
    #$Op=~s/>=/&ge;/g;
    if($Op eq "=")
    { # do not show "="
        $Op="";
    }
    if($Op) {
        $Op = $Op." ";
    }
    return $Op;
}

sub createFileView($$$)
{
    my ($File, $V, $Dir) = @_;
    
    my $Path = $PackageFiles{$V}{$File};
    
    if(not -T $Path)
    {
        return undef;
    }
    
    my $Name = getFilename($File);
    my $Content = readFile($Path);
    my $CssStyles = readModule("Styles", "View.css");
    
    $Content = htmlSpecChars($Content);
    
    if($Name=~/\.patch\Z/)
    {
       while($Content=~s&(\A|\n)(\+.*?)(\n|\Z)&$1<span class='add'>$2</span>$3&mg){};
       while($Content=~s&(\A|\n)(\-.*?)(\n|\Z)&$1<span class='rm'>$2</span>$3&mg){};
    }
    
    $Content = "<pre class='view'>".$Content."</pre>\n";
    
    $Content = "<table cellspacing='0' cellpadding='0'>\n<tr>\n<td class='header'>\n".$Name."</td><td class='plain'><a href=\'".encodeUrl($Name)."\'>plain</a></td>\n</tr>\n<tr>\n<td valign='top' colspan='2'>\n".$Content."</td>\n</tr>\n</table>\n";
    $Content = composeHTMLHead($Name, "", "View file ".$File, $CssStyles, "")."\n<body>\n".$Content;
    $Content .= "</body></html>";
    
    my $R = $Dir."/".$File."-view.html";
    writeFile($REPORT_DIR."/".$R, $Content);
    
    # plain copy
    copy($Path, $REPORT_DIR."/".$Dir."/".getDirname($File)."/");
    
    return $R;
}

sub getReportFiles()
{
    my $Report = "";
    my $JSort = "title='sort' onclick='javascript:sort(this, 1)' style='cursor:pointer'";
    foreach my $Format (sort {$FormatInfo{$b}{"Weight"}<=>$FormatInfo{$a}{"Weight"}}
    sort {lc($FormatInfo{$a}{"Summary"}) cmp lc($FormatInfo{$b}{"Summary"})} keys(%FileChanges))
    {
        my $Total = $FileChanges{$Format}{"Total"};
        
        if($HideUnchanged) {
            $Total = $FileChanges{$Format}{"Added"} + $FileChanges{$Format}{"Removed"} + $FileChanges{$Format}{"Changed"};
        }
        
        if(not $Total) {
            next;
        }
        
        if($HideUnchanged)
        {
            if(not $Total)
            { # do not show unchanged files
                next;
            }
            
            $FileChanges{$Format}{"Total"} = $Total;
        }
        
        $Report .= "<a name='".$FormatInfo{$Format}{"Anchor"}."'></a>\n";
        $Report .= "<h2>".$FormatInfo{$Format}{"Title"}." (".$FileChanges{$Format}{"Total"}.")</h2><hr/>\n";
        $Report .= "<table class='summary highlight'>\n";
        $Report .= "<tr>\n";
        $Report .= "<th $JSort>Name</th>\n";
        $Report .= "<th $JSort>Status</th>\n";
        if($Format ne "DIR")
        {
            $Report .= "<th $JSort>Delta</th>\n";
            $Report .= "<th>Visual<br/>Diff</th>\n";
            
            if($ShowDetails)
            {
                $Report .= "<th>Detailed<br/>Report</th>\n";
                
                if($Format eq "SHARED_OBJECT"
                or $Format eq "KERNEL_MODULE"
                or $Format eq "DEBUG_INFO"
                or $Format eq "STATIC_LIBRARY")
                {
                    $Report .= "<th>ABI<br/>Dumps</th>\n";
                    if($Debug) {
                        $Report .= "<th>DWARF<br/>Dumps</th>\n";
                    }
                }
            }
        }
        $Report .= "</tr>\n";
        my %Details = %{$FileChanges{$Format}{"Details"}};
        foreach my $File (sort {lc($a) cmp lc($b)} keys(%Details))
        {
            if($RenamedFiles_R{$File}
            or $MovedFiles_R{$File}) {
                next;
            }
            
            my %Info = %{$Details{$File}};
            
            if($HideUnchanged)
            {
                if($Info{"Status"} eq "unchanged")
                { # do not show unchanged files
                    next;
                }
            }
            
            my ($Join, $Color1, $Color2) = ("", "", "");
            if($Info{"Status"} eq "renamed"
            or $Info{"Status"} eq "moved")
            {
                $Join = " rowspan='2'";
                $Color1 = " failed";
                $Color2 = " new";
            }
            elsif($Info{"Status"} eq "added") {
                $Color1 = " new";
            }
            elsif($Info{"Status"} eq "removed") {
                $Color1 = " failed";
            }
            
            my $ShowFile = $File;
            
            if(defined $ListAddedRemoved
            and $Info{"Status"}=~/added|removed/)
            {
                my $FN = getFilename($ShowFile);
                if($Info{"Status"} eq "added")
                {
                    if(my $View = encodeUrl(createFileView($File, 2, "view/added"))) {
                        $ShowFile=~s&(\A|/)(\Q$FN\E)\Z&$1<a href=\'$View\' target=\'$LinksTarget\' title='View file'>$2</a>&;
                    }
                }
                elsif($Info{"Status"} eq "removed")
                {
                    if(my $View = encodeUrl(createFileView($File, 1, "view/removed"))) {
                        $ShowFile=~s&(\A|/)(\Q$FN\E)\Z&$1<a href=\'$View\' target=\'$LinksTarget\' title='View file'>$2</a>&;
                    }
                }
            }
            
            $Report .= "<tr>\n";
            $Report .= "<td class='left f_path$Color1\'>$ShowFile</td>\n";
            if($Info{"Status"} eq "changed") {
                $Report .= "<td class='warning'>".$Info{"Status"}."</td>\n";
            }
            elsif($Info{"Status"} eq "unchanged") {
                $Report .= "<td class='passed'>".$Info{"Status"}."</td>\n";
            }
            elsif($Info{"Status"} eq "removed") {
                $Report .= "<td class='failed'>".$Info{"Status"}."</td>\n";
            }
            elsif($Info{"Status"} eq "added") {
                $Report .= "<td class='new'>".$Info{"Status"}."</td>\n";
            }
            elsif($Info{"Status"} eq "renamed") {
                $Report .= "<td class='renamed'$Join>".$Info{"Status"}."</td>\n";
            }
            elsif($Info{"Status"} eq "moved") {
                $Report .= "<td class='moved'$Join>".$Info{"Status"}."</td>\n";
            }
            else {
                $Report .= "<td>unknown</td>\n";
            }
            if($Format ne "DIR")
            {
                if(not $QuickMode and not $Info{"Skipped"}
                and $Info{"Status"}=~/\A(changed|moved|renamed)\Z/) {
                    $Report .= "<td class='value'$Join>".showNumber($Info{"Rate"}*100)."%</td>\n";
                }
                else {
                    $Report .= "<td$Join></td>\n";
                }
                if(my $Link = $Info{"Diff"}) {
                    $Report .= "<td$Join><a href='".encodeUrl($Link)."' target=\'$LinksTarget\'>diff</a></td>\n";
                }
                elsif($Info{"Empty"}) {
                    $Report .= "<td$Join></td>\n";
                }
                elsif($Info{"Skipped"}) {
                    $Report .= "<td$Join>skipped</td>\n";
                }
                else {
                    $Report .= "<td$Join></td>\n";
                }
                
                if($ShowDetails)
                {
                    if(my $Link = $Info{"Report"}) {
                        $Report .= "<td$Join><a href='".encodeUrl($Link)."' target=\'$LinksTarget\'>report</a></td>\n";
                    }
                    else {
                        $Report .= "<td$Join></td>\n";
                    }
                    
                    if($Format eq "SHARED_OBJECT"
                    or $Format eq "KERNEL_MODULE"
                    or $Format eq "DEBUG_INFO"
                    or $Format eq "STATIC_LIBRARY")
                    {
                        if(defined $Info{"ABIDump"})
                        {
                            my $Link1 = $Info{"ABIDump"}{1};
                            my $Link2 = $Info{"ABIDump"}{2};
                            
                            $Report .= "<td$Join><a href='".encodeUrl($Link1)."' target=\'$LinksTarget\'>1</a>, <a href='".encodeUrl($Link2)."' target=\'$LinksTarget\'>2</a></td>\n";
                        }
                        else {
                            $Report .= "<td$Join></td>\n";
                        }
                        if($Debug)
                        {
                            if(defined $Info{"DWARFDump"})
                            {
                                my $Link1 = $Info{"DWARFDump"}{1};
                                my $Link2 = $Info{"DWARFDump"}{2};
                                
                                $Report .= "<td$Join><a href='".encodeUrl($Link1)."' target=\'$LinksTarget\'>1</a>, <a href='".encodeUrl($Link2)."' target=\'$LinksTarget\'>2</a></td>\n";
                            }
                            else {
                                $Report .= "<td$Join></td>\n";
                            }
                        }
                    }
                }
            }
            $Report .= "</tr>\n";
            if(my $RenamedTo = $RenamedFiles{$File}) {
                $Report .= "<tr><td class='left f_path $Color2\'>".$RenamedTo."</td></tr>\n";
            }
            elsif(my $MovedTo = $MovedFiles{$File}) {
                $Report .= "<tr><td class='left f_path $Color2\'>".$MovedTo."</td></tr>\n";
            }
        }
        $Report .= "</table>\n";
    }
    return $Report;
}

sub writeFile($$)
{
    my ($Path, $Content) = @_;
    
    if(my $Dir = getDirname($Path)) {
        mkpath($Dir);
    }
    
    open(FILE, ">", $Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

sub readFile($)
{
    my $Path = $_[0];
    
    open(FILE, "<", $Path);
    local $/ = undef;
    my $Content = <FILE>;
    close(FILE);
    
    return $Content;
}

sub getPrefixes($$)
{
    my @Parts = split(/[\/]+/, $_[0]);
    my $Prefix = $Parts[$#Parts];
    my @Res = ();
    foreach (1 .. $_[1])
    {
        if($_<$#Parts)
        {
            $Prefix = $Parts[$#Parts-$_]."/".$Prefix;
            push(@Res, $Prefix);
        }
    }
    return @Res;
}

sub getFilename($)
{ # much faster than basename() from File::Basename module
    if($_[0]=~/([^\/]+)[\/]*\Z/) {
        return $1;
    }
    return "";
}

sub getDirname($)
{ # much faster than dirname() from File::Basename module
    if($_[0]=~/\A(.*?)[\/]+[^\/]*[\/]*\Z/) {
        return $1;
    }
    return "";
}

sub sepPath($) {
    return (getDirname($_[0]), getFilename($_[0]));
}

sub exitStatus($$)
{
    my ($Code, $Msg) = @_;
    printMsg("ERROR", $Msg);
    exit($ERROR_CODE{$Code});
}

sub printMsg($$)
{
    my ($Type, $Msg) = @_;
    if($Type!~/\AINFO/) {
        $Msg = $Type.": ".$Msg;
    }
    if($Type!~/_C\Z/) {
        $Msg .= "\n";
    }
    if($Type eq "ERROR") {
        print STDERR $Msg;
    }
    else {
        print $Msg;
    }
}

sub cutPathPrefix($$)
{
    my ($Path, $Prefix) = @_;
    
    if(not $Prefix) {
        return $Path;
    }
    
    $Prefix=~s/[\/]+\Z//;
    $Path=~s/\A\Q$Prefix\E([\/]+|\Z)//;
    
    return $Path;
}

sub getAbsPath($)
{ # abs_path() should NOT be called for absolute inputs
  # because it can change them (symlinks)
    my $Path = $_[0];
    if($Path!~/\A\//) {
        $Path = abs_path($Path);
    }
    return $Path;
}

sub cmdFind(@)
{
    if(not checkCmd("find")) {
        exitStatus("Not_Found", "can't find a \"find\" command");
    }
    
    my $Path = shift(@_);
    
    my ($Type, $Name, $MaxDepth, $UseRegex) = ();
    
    if(@_) {
        $Type = shift(@_);
    }
    if(@_) {
        $Name = shift(@_);
    }
    if(@_) {
        $MaxDepth = shift(@_);
    }
    if(@_) {
        $UseRegex = shift(@_);
    }
    
    $Path = getAbsPath($Path);
    
    if(-d $Path and -l $Path
    and $Path!~/\/\Z/)
    { # for directories that are symlinks
        $Path .= "/";
    }
    
    my $Cmd = "find \"$Path\"";
    if($MaxDepth) {
        $Cmd .= " -maxdepth $MaxDepth";
    }
    if($Type) {
        $Cmd .= " -type $Type";
    }
    if($Name and not $UseRegex)
    { # wildcards
        $Cmd .= " -name \"$Name\"";
    }
    
    my $Res = `$Cmd 2>\"$TMP_DIR/null\"`;
    if($?) {
        printMsg("ERROR", "problem with \'find\' utility ($?): $!");
    }
    
    my @Files = split(/\n/, $Res);
    if($Name and $UseRegex)
    { # regex
        @Files = grep { /\A$Name\Z/ } @Files;
    }
    
    return @Files;
}

sub generateTemplate()
{
    writeFile("VERSION.xml", $DescriptorTemplate."\n");
    printMsg("INFO", "XML-descriptor template ./VERSION.xml has been generated");
}

sub isSCM_File($)
{ # .svn, .git, .bzr, .hg and CVS
    my $Dir = getDirname($_[0]);
    my $Name = getFilename($_[0]);
    
    if($Dir=~/(\A|[\/\\])\.(svn|git|bzr|hg)([\/\\]|\Z)/) {
        return uc($2);
    }
    elsif($Name=~/\A\.(git|cvs|hg).*/)
    { # .gitignore, .gitattributes, .gitmodules, etc.
      # .cvsignore
        return uc($1);
    }
    elsif($Dir=~/(\A|[\/\\])(CVS)([\/\\]|\Z)/) {
        return "cvs";
    }
    
    return undef;
}

sub identifyFile($$)
{
    my ($Name, $Type) = @_;
    if($Type eq "iName"
    or $Type eq "iExt") {
        $Name=lc($Name);
    }
    if($Type eq "Name"
    or $Type eq "iName")
    {
        if(my $ID = $FileFormat{$Type}{$Name})
        { # Exact name
            return $ID;
        }
    }
    if($Type eq "Ext"
    or $Type eq "iExt")
    {
        if($Name=~/\.(\w+\.\w+)(\.(in|\d+)|)\Z/i)
        { # Double extension
            if(my $ID = $FileFormat{$Type}{$1}) {
                return $ID;
            }
        }
        if($Name=~/\.(\w+)(\.(in|\d+)|)\Z/i)
        { # Single extension
            if(my $ID = $FileFormat{$Type}{$1}) {
                return $ID;
            }
        }
    }
    return "";
}

sub getFormat($)
{
    my $Path = $_[0];
    
    if(defined $Cache{"getFormat"}{$Path}) {
        return $Cache{"getFormat"}{$Path};
    }
    my $Format = getFormat_I($Path);
    
    if($Format=~/\A(OTHER|INFORM|DATA|TEXT)\Z/)
    { # by directory
        if(my $Dir = getDirname($PathName{$Path}))
        {
            my $ID = undef;
            
            # by dir
            foreach my $SDir (reverse(split(/\//, $Dir)))
            {
                if($ID = $DirFormat{$SDir})
                {
                    $Format = $ID;
                    last;
                }
            }
            
            if(not defined $ID)
            {
                # by subdir
                foreach my $SDir (keys(%DirFormat))
                {
                    if(index($SDir, "/")==-1) {
                        next;
                    }
                    
                    if(index($Dir, $SDir)!=-1)
                    {
                        if($Dir=~/(\A|\/)\Q$SDir\E(\/|\Z)/)
                        {
                            $Format = $DirFormat{$SDir};
                            last;
                        }
                    }
                }
            }
        }
    }
    
    if($Format eq "OTHER")
    {
        my $Bytes = readBytes($Path);
        if(my $ID = $BytesFormat{$Bytes}) {
            $Format = $ID;
        }
        
        my $Ext = getExt($Path);
        if(not $Ext
        and $Bytes eq "7f454c46")
        { # ELF executable
            $Format = "EXE";
        }
    }
    
    if($Format eq "OTHER")
    { # semi-automatic
        if(my $Info = getType($Path))
        {
            # by terms
            my @Terms = getTerms($Info);
            foreach my $Term (@Terms)
            {
                if($Term eq "TEXT"
                or $Term eq "DATA") {
                    next;
                }
                if(defined $FormatInfo{$Term}
                and my $ID = $FormatInfo{$Term}{"ID"})
                {
                    $Format = $ID;
                    last;
                }
                elsif(my $ID2 = $TermFormat{$Term})
                {
                    $Format = $ID2;
                    last;
                }
            }
        }
    }
    
    if($Format eq "OTHER")
    { # automatic
        if(my $Info = getType($Path))
        {
            if($Info=~/compressed|Zip archive/i) {
                $Format = "ARCHIVE";
            }
            elsif($Info=~/data/i) {
                $Format = "DATA";
            }
            elsif($Info=~/text/i) {
                $Format = "TEXT";
            }
            elsif($Info=~/executable/i) {
                $Format = "EXE";
            }
            elsif($Info=~/\AELF\s/) {
                $Format = "ELF_BINARY";
            }
        }
    }
    
    if($Format eq "SHARED_OBJECT")
    {
        if(getType($Path)=~/ASCII/i)
        {
            if(readFilePart($Path, 1)=~/GNU ld script/i) {
                $Format = "GNU_LD_SCRIPT";
            }
            else {
                $Format = "TEXT";
            }
        }
    }
    
    if($Format eq "SHARED_OBJECT"
    or $Format eq "KERNEL_MODULE"
    or $Format eq "DEBUG_INFO")
    { # double-check
        if(readBytes($Path) ne "7f454c46") {
            $Format = "OTHER";
        }
    }
    
    if(not defined $FormatInfo{$Format}
    or not $FormatInfo{$Format}{"Summary"})
    { # Unknown
        $Format = "OTHER";
    }
    
    if($Format eq "OTHER")
    {
        if($AllText) {
            $Format = "TEXT";
        }
    }
    
    return ($Cache{"getFormat"}{$Path}=$Format);
}

sub getFormat_I($)
{
    my $Path = $_[0];
    
    my $Dir = getDirname($Path);
    my $Name = getFilename($Path);
    
    $Name=~s/\~\Z//g; # backup files
    
    if(-l $Path) {
        return "SYMLINK";
    }
    elsif(-d $Path) {
        return "DIR";
    }
    elsif(my $ID = identifyFile($Name, "Name"))
    { # check by exact name (case sensitive)
        return $ID;
    }
    elsif(my $ID2 = identifyFile($Name, "iName"))
    { # check by exact name (case insensitive)
        return $ID2;
    }
    elsif($Path=~/svn|git|bzr|hg|cvs/i
    and my $Kind = isSCM_File($Path)) {
        return $Kind;
    }
    elsif($Name!~/\.(\w+)\Z/i
    and $Dir=~/(\A|\/)(include|includes)(\/|\Z)/)
    { # include/QtWebKit/QWebSelectData
      # includes/KService
        return "HEADER";
    }
    elsif($Name=~/\.(so)(|\.\d[0-9\-\.\_]*)\Z/i)
    { # Shared library
        return "SHARED_OBJECT";
    }
    elsif($Name=~/\A(readme)(\W|\_|\Z)/i
    or $Name=~/(\W|\_)(readme)(\.txt|)\Z/i) {
        return "README";
    }
    elsif($Name=~/\A(license|licenses|licence|copyright|copying)(\W|\_|\Z)/i
    or $Name=~/\.(license|licence)\Z/i or $Name=~/\A(gpl|lgpl|bsd|qpl|artistic)(\W|\_|)(v|)([\d\.]+|)(\.txt|)\Z/i)
    { # APACHE.license
      # LGPL.license
      # COPYRIGHT.IBM
        return "LICENSE";
    }
    elsif($Name=~/\A(changelog|changes|relnotes)(\W|\Z)/i
    or $Name=~/\A(NEWS)(\W|\Z)/)
    { # ChangeLog-2003-10-25
      # docs/CHANGES
      # freetype/ChangeLog
        return "CHANGELOG";
    }
    elsif($Name=~/\A(INSTALL|TODO)(\.|\-|\Z)/
    or $Name=~/\A[A-Z\-\_]+(\.txt|\.TXT|\Z)/
    or $Name=~/\A[A-Z\_]+\.[A-Z\_]+\Z/)
    { # HOWTO.DEBUG, BUGS, WISHLIST.TXT
        return "INFORM";
    }
    elsif((($Name=~/\.(gz|xz|lzma)\Z/i or $Name=~/\.(\d+)\Z/i)
    and $Dir=~/\/(man\d*|manpages)(\/|\Z)/)
    or ($Name=~/\.(\d+)\Z/i and $Dir=~/\/(doc|docs|src|libs|utils)(\/|\Z)/)
    or $Name=~/\.(man)\Z/
    or ($Name=~/[a-z]{3,}\.(\d+)\Z/i and $Name!~/\.($ARCHIVE_EXT)\./i and $Dir!~/log/i))
    { # harmattan/manpages/uic.1
      # t1utils-1.36/t1asm.1
        return "MANPAGE";
    }
    elsif($Name=~/\.info(|\-\d+)(|\.(gz|xz|lzma))\Z/i
    and $Dir=~/\/(info|share|doc|docs)(\/|\Z)/)
    { # /usr/share/info/libc.info-1.gz
        return "INFODOC";
    }
    elsif($Name=~/\ADoxyfile(\W|\Z)/i) {
        return "DOXYGEN";
    }
    elsif($Name=~/(make|conf)[^\.]*(\.in)+\Z/i) {
        return "AUTOMAKE";
    }
    elsif($Name=~/\A(g|)(makefile)(\.|\Z)/i) {
        return "MAKEFILE";
    }
    elsif($Name=~/\A(CMakeLists.*\.txt)\Z/i) {
        return "CMAKE";
    }
    elsif(my $ID3 = identifyFile($Name, "Ext"))
    { # check by extension (case sensitive)
        return $ID3;
    }
    elsif(my $ID4 = identifyFile($Name, "iExt"))
    { # check by extension (case insensitive)
        return $ID4;
    }
    elsif(substr($Name, 0, 1) eq ".") {
        return "HIDDEN";
    }
    return "OTHER";
}

sub getTerms($)
{
    my $Str = $_[0];
    my %Terms = ();
    my ($Prev, $Num) = ("", 0);
    while($Str=~s/([\w\-]+)//)
    {
        if($Prev) {
            $Terms{uc($Prev."_".$1)}=$Num++;
        }
        $Terms{uc($1)}=$Num++;
        $Prev = $1;
    }
    return sort {$Terms{$a}<=>$Terms{$b}} keys(%Terms);
}

sub parseTag($$)
{
    my ($CodeRef, $Tag) = @_;
    return "" if(not $CodeRef or not ${$CodeRef} or not $Tag);
    if(${$CodeRef}=~s/\<\Q$Tag\E\>((.|\n)+?)\<\/\Q$Tag\E\>//)
    {
        my $Content = $1;
        $Content=~s/(\A\s+|\s+\Z)//g;
        return $Content;
    }
    else {
        return "";
    }
}

sub readDescriptor($$)
{
    my ($Version, $Path) = @_;
    
    my $Content = readFile($Path);
    if(not $Content) {
        exitStatus("Error", "XML-descriptor is empty");
    }
    if($Content!~/\</) {
        exitStatus("Error", "XML-descriptor has a wrong format");
    }
    $Content=~s/\/\*(.|\n)+?\*\///g;
    $Content=~s/<\!--(.|\n)+?-->//g;
    if(my $GV = parseTag(\$Content, "version")) {
        $Group{"V".$Version} = $GV;
    }
    else {
        exitStatus("Error", "version in the XML-descriptor is not specified (<version> section)");
    }
    if(my $GN = parseTag(\$Content, "group")) {
        $Group{"Name".$Version} = $GN;
    }
    else {
        exitStatus("Error", "group name in the XML-descriptor is not specified (<group> section)");
    }
    if(my $Pkgs = parseTag(\$Content, "packages"))
    {
        foreach my $Path (split(/\s*\n\s*/, $Pkgs))
        {
            if(not -e $Path) {
                exitStatus("Access_Error", "can't access \'".$Path."\'");
            }
            if(-d $Path)
            {
                my @Files = cmdFind($Path, "f", "*.rpm");
                @Files = (@Files, cmdFind($Path, "f", "*.src.rpm"));
                if(not @Files)
                { # search for DEBs
                    @Files = (@Files, cmdFind($Path, "f", "*.deb"));
                }
                foreach my $F (@Files) {
                    registerPackage($F, $Version);
                }
            }
            else {
                registerPackage($Path, $Version);
            }
        }
    }
    else {
        exitStatus("Error", "packages in the XML-descriptor are not specified (<packages> section)");
    }
    foreach my $Path (split(/\s*\n\s*/, parseTag(\$Content, "skip_files")))
    {
        my ($CPath, $Type) = classifyPath($Path);
        $SkipFiles{$Version}{$Type}{$CPath} = 1;
    }
}

sub classifyPath($)
{
    my $Path = $_[0];
    if($Path=~/[\*\[]/)
    { # wildcard
        $Path=~s/\*/.*/g;
        $Path=~s/\\/\\\\/g;
        return ($Path, "Pattern");
    }
    elsif($Path=~/[\/\\]/)
    { # directory or relative path
        return ($Path, "Path");
    }
    
    return ($Path, "Name");
}

sub skipFileCompare($$)
{
    my ($Path, $Version) = @_;
    
    my $Name = getFilename($Path);
    if($SkipFiles{$Version}{"Name"}{$Name}) {
        return 1;
    }
    foreach my $Dir (keys(%{$SkipFiles{$Version}{"Path"}}))
    {
        if($Path=~/\Q$Dir\E/) {
            return 1;
        }
    }
    foreach my $Pattern (keys(%{$SkipFiles{$Version}{"Pattern"}}))
    {
        if($Name=~/($Pattern)/) {
            return 1;
        }
        if($Pattern=~/[\/\\]/ and $Path=~/($Pattern)/) {
            return 1;
        }
    }
    return 0;
}

sub sepDep($)
{
    my $Dep = $_[0];
    if($Dep=~/\A(.+?)(\s+|\[|\()(=|==|<=|>=|<|>)\s+(.+?)(\]|\)|\Z)/)
    {
        my ($N, $O, $V) = ($1, $3, $4);
        # canonify version (1:3.2.5-5:2011.0)
        $V=~s/\A[^\-\:]+\://;# cut prefix (1:)
        return ($N, $O, $V);
    }
    
    return ($Dep, "", "");
}

sub registerPackage(@)
{
    my ($Path, $Version, $Ph) = @_;
    
    if(not $Path) {
        return ();
    }
    
    my $PkgName = getFilename($Path);
    my $PkgFormat = getFormat($Path);
    
    my ($CPath, $Attr) = ();
    if($Ph)
    { # already opened
        ($CPath, $Attr) = ($Ph->{"CPath"}, $Ph->{"Attr"});
    }
    else
    { # not opened
        ($CPath, $Attr) = readPackage($Path, $Version);
    }
    
    $TargetPackages{$Version}{$PkgName} = 1;
    $Group{"Count$Version"} += 1;
    
    # search for all files
    my @Files = cmdFind($CPath);
    foreach my $File (sort @Files)
    {
        my $FName = cutPathPrefix($File, $CPath);
        if($PkgFormat eq "RPM"
        or $PkgFormat eq "DEB")
        { # files installed to the system
            $FName = "/".$FName;
        }
        elsif($PkgFormat eq "ARCHIVE")
        {
            if(my $RmPrefix = $RemovePrefix{$Version})
            { # cut common prefix from all files
                $FName = cutPathPrefix($FName, $RmPrefix);
            }
        }
        if(not $FName) {
            next;
        }
        
        if(defined $SkipPattern)
        {
            if(skipFile($FName)) {
                next;
            }
        }
        
        $PackageFiles{$Version}{$FName} = $File;
        $PathName{$File} = $FName;
        
        if(not defined $CompareDirs
        and not defined $SkipSubArchives
        and not getDirname($FName)
        and getFormat($File) eq "ARCHIVE")
        { # go into archives (for SRPM)
            my $SubDir = "$TMP_DIR/xcontent$Version/$FName";
            unpackArchive($File, $SubDir);
            
            my @SubContents = listDir($SubDir);
            if($#SubContents==0 and -d $SubDir."/".$SubContents[0])
            { # libsample-x.y.z.tar.gz/libsample-x.y.z
                $SubDir .= "/".$SubContents[0];
            }
            
            foreach my $SubFile (cmdFind($SubDir))
            { # search for all files in archive
                my $SFName = cutPathPrefix($SubFile, $SubDir);
                if(not $SFName) {
                    next;
                }
                
                if(defined $SkipPattern)
                {
                    if(skipFile($SFName)) {
                        next;
                    }
                }
                
                $PackageFiles{$Version}{$SFName} = $SubFile;
            }
        }
    }
    
    delete($PackageFiles{$Version}{"/"});
    
    if($CheckUsage) {
        checkUsage($Attr->{"Name"});
    }
    
    return $Attr;
}

sub checkUsage($)
{
    my $Name = $_[0];
    if($PackageManager eq "urpm")
    {
        foreach my $Pkg (split(/\s*\n\s*/, `urpmq --whatrequires $Name`))
        {
            $PackageUsage{$Name}{"UsedBy"}{$Pkg} = 1;
            $TotalUsage{$Pkg}=1;
        }
    }
}

sub listDir($)
{
    my $Path = $_[0];
    
    opendir(my $DH, $Path);
    
    if(not $DH)
    { # error
        return ();
    }
    
    my @Contents = grep { $_ ne "." && $_ ne ".." } readdir($DH);
    return @Contents;
}

sub getArchiveFormat($)
{
    my $Pkg = getFilename($_[0]);
    foreach (sort {length($b)<=>length($a)} keys(%ArchiveFormats))
    {
        my $P = $ArchiveFormats{$_};
        if($Pkg=~/\.($P)(|\.\d+)\Z/i) {
            return $_;
        }
    }
    return undef;
}

sub unpackArchive($$)
{ # TODO: tar -xf for all tar.* formats
    my ($Pkg, $OutDir) = @_;
    
    my $Format = getArchiveFormat($Pkg);
    if(not $Format)
    {
        printMsg("ERROR", "can't determine format of archive \'".getFilename($Pkg)."\'");
        return 1;
    }
    
    my $Cmd = undef;
    
    if($Format=~/TAR\.\w+/i or $Format eq "TAR") {
        $Cmd = "tar -xf \"$Pkg\" --directory=\"$OutDir\"";
    }
    elsif($Format eq "GZ") {
        $Cmd = "cp -f \"$Pkg\" \"$OutDir\" && cd \"$OutDir\" && gunzip \"".getFilename($Pkg)."\"";
    }
    elsif($Format eq "LZMA") {
        $Cmd = "cp -f \"$Pkg\" \"$OutDir\" && cd \"$OutDir\" && unlzma \"".getFilename($Pkg)."\"";
    }
    elsif($Format eq "XZ") {
        $Cmd = "cp -f \"$Pkg\" \"$OutDir\" && cd \"$OutDir\" && unxz \"".getFilename($Pkg)."\"";
    }
    elsif($Format eq "ZIP") {
        $Cmd = "unzip -o \"$Pkg\" -d \"$OutDir\"";
    }
    elsif($Format eq "JAR") {
        $Cmd = "cd \"$OutDir\" && jar -xf \"$Pkg\"";
    }
    elsif($Format eq "APK") {
        $Cmd = "apktool d -f -o \"$OutDir\" \"$Pkg\"";

        if(not defined $SkipPattern) {
            $SkipPattern = "apktool.yml|original\/META-INF";
        }
        elsif(not $SkipPattern=~m/apktool.yml|original\/META-INF/) {
            $SkipPattern = "apktool.yml|original\/META-INF|$SkipPattern";
        }
    }
    
    if($Cmd)
    {
        mkpath($OutDir);
        my $TmpFile = $TMP_DIR."/output";
        qx/$Cmd >$TmpFile 2>&1/;
        return 0;
    }
    
    return 1;
}

sub readPackage($$)
{
    my ($Path, $Version) = @_;
    
    if(not $Path) {
        return ();
    }
    
    my $Format = getFormat($Path);
    
    if($CompareDirs and $Format eq "DIR")
    {
        return ($Path, {});
    }
    
    my $CDir = "$TMP_DIR/content$Version";
    my $CPath = $CDir."/".getFilename($Path);
    
    my %Attr = ();
    
    if($Format eq "DEB")
    { # Deb package
        if(not checkCmd("dpkg-deb")) {
            exitStatus("Not_Found", "can't find \"dpkg-deb\"");
        }
        mkpath($CPath);
        system("dpkg-deb --extract \"$Path\" \"$CPath\"");
        if($?) {
            exitStatus("Error", "can't extract package v$Version");
        }
        if(not checkCmd("dpkg")) {
            exitStatus("Not_Found", "can't find \"dpkg\"");
        }
        my $Info = `dpkg -f $Path`;
        if($Info=~/Version\s*:\s*(.+)/) {
            $Attr{"Version"} = $1;
        }
        if($Info=~/Package\s*:\s*(.+)/) {
            $Attr{"Name"} = $1;
        }
        if($Info=~/Architecture\s*:\s*(.+)/) {
            $Attr{"Arch"} = $1;
        }
        foreach my $Kind ("Depends", "Provides")
        {
            if($Info=~/$Kind\s*:\s*(.+)/)
            {
                foreach my $Dep (split(/\s*,\s*/, $1))
                {
                    my ($N, $Op, $V) = sepDep($Dep);
                    %{$PackageDeps{$Version}{$Kind}{$N}} = ( "Op"=>$Op, "V"=>$V );
                    $TotalDeps{$Kind." ".$N} = 1;
                }
            }
        }
        $PackageInfo{$Attr{"Name"}}{"V$Version"} = $Info;
        $Group{"Format"}{$Format} = 1;
    }
    elsif($Format eq "RPM" or $Format eq "SRPM")
    { # RPM or SRPM package
        if(not checkCmd("rpm"))
        { # rpm and rpm2cpio
            exitStatus("Not_Found", "can't find \"rpm\"");
        }
        if(not checkCmd("cpio")) {
            exitStatus("Not_Found", "can't find \"cpio\"");
        }
        mkpath($CPath);
        system("cd \"$CPath\" && rpm2cpio \"".abs_path($Path)."\" | cpio -id --quiet");
        if($?) {
            exitStatus("Error", "can't extract package v$Version");
        }
        ($Attr{"Version"}, $Attr{"Release"},
        $Attr{"Name"}, $Attr{"Arch"}) = split(",", queryRPM($Path, "--queryformat \%{version},\%{release},\%{name},\%{arch}"));
        if($Attr{"Release"}) {
            $Attr{"Version"} .= "-".$Attr{"Release"};
        }
        foreach my $Kind ("requires", "provides", "suggests")
        {
            foreach my $D (split("\n", queryRPM($Path, "--".$Kind)))
            {
                my ($N, $Op, $V) = sepDep($D);
                %{$PackageDeps{$Version}{$Kind}{$N}} = ( "Op"=>$Op, "V"=>$V );
                $TotalDeps{$Kind." ".$N} = 1;
            }
        }
        $PackageInfo{$Attr{"Name"}}{"V$Version"} = queryRPM($Path, "--info");
        $Group{"Format"}{$Format} = 1;
    }
    elsif($Format eq "ARCHIVE")
    { # TAR.GZ and others
        if(unpackArchive(abs_path($Path), $CPath)!=0) {
            exitStatus("Error", "can't extract package \'".getFilename($Path)."\'");
        }
        
        if(my ($N, $V) = parseVersion(getFilename($Path))) {
            ($Attr{"Name"}, $Attr{"Version"}) = ($N, $V);
        }
        if(not $Attr{"Version"})
        { # default version
            $Attr{"Version"} = $Version==1?"X":"Y";
        }
        if(not $Attr{"Name"})
        { # default name
            $Attr{"Name"} = getFilename($Path);
            $Attr{"Name"}=~s/\.($ARCHIVE_EXT)\Z//;
        }
        $Group{"Format"}{uc(getExt($Path))} = 1;
    }
    return ($CPath, \%Attr);
}

sub parseVersion($)
{
    my $Name = $_[0];
    if(my $Extension = getExt($Name)) {
        $Name=~s/\.(\Q$Extension\E)\Z//;
    }
    if($Name=~/\A(.+[a-z])[\-\_](v|ver|)(\d.+?)\Z/i)
    { # libsample-N
      # libsample-vN
        return ($1, $3);
    }
    elsif($Name=~/\A([\d\.\-]+)\Z/i)
    { # X.Y-Z
        return ("", $Name);
    }
    elsif($Name=~/\A(.+?)[\-\_]*(\d[\d\.\-]*)\Z/i)
    { # libsampleN
      # libsampleN-X.Y
        return ($1, $2);
    }
    elsif($Name=~/\A(.+)[\-\_](v|ver|)(.+?)\Z/i)
    { # libsample-N
      # libsample-vN
        return ($1, $3);
    }
    elsif($Name=~/\A([a-z_\-]+)(\d.+?)\Z/i)
    { # libsampleNb
        return ($1, $2);
    }
    return ();
}

sub getExt($)
{
    if($_[0]=~/\.($ARCHIVE_EXT)\Z/) {
        return $1;
    }
    elsif($_[0]=~/\.(\w+)(\.in|)\Z/) {
        return $1;
    }
    return "";
}

sub queryRPM($$)
{
    my ($Path, $Query) = @_;
    return `rpm -qp $Query \"$Path\" 2>$TMP_DIR/null`;
}

sub composeHTMLHead($$$$$)
{
    my ($Title, $Keywords, $Description, $Styles, $Scripts) = @_;
    return "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">
    <html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\">
    <head>
    <meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />
    <meta name=\"viewport\" content=\"width=device-width,initial-scale=1\" />
    <meta name=\"keywords\" content=\"$Keywords\" />
    <meta name=\"description\" content=\"$Description\" />
    <title>
        $Title
    </title>
    <style type=\"text/css\">
    $Styles
    </style>
    <script type=\"text/javascript\" language=\"JavaScript\">
    <!--
    $Scripts
    -->
    </script>
    </head>";
}

sub getTitle()
{
    if($TargetTitle) {
        return $TargetTitle;
    }
    
    return $Group{"Name"};
}

sub getHeader()
{
    my $Header = "";
    
    if($CompareDirs and not $TargetName)
    {
        $Header = "Changes report between <span style='color:Blue;'>".$Group{"Name1"}."/</span> and <span style='color:Blue;'>".$Group{"Name2"}."/</span> directories";
    }
    elsif($CheckMode eq "Group") {
        $Header = "Changes report for the <span style='color:Blue;'>".getTitle()."</span> group of packages between <span style='color:Red;'>".$Group{"V1"}."</span> and <span style='color:Red;'>".$Group{"V2"}."</span> versions";
    }
    else
    { # single package
        $Header = "Changes report for the <span style='color:Blue;'>".getTitle()."</span> package between <span style='color:Red;'>".$Group{"V1"}."</span> and <span style='color:Red;'>".$Group{"V2"}."</span> versions";
    }
    
    if($HideUnchanged) {
        $Header .= " (hidden unchanged files)";
    }
    
    return "<h1>".$Header."</h1>";
}

sub showNumber($)
{
    if($_[0])
    {
        my $Num = cutNumber($_[0], 2, 0);
        if($Num eq "0")
        {
            foreach my $P (3 .. 7)
            {
                $Num = cutNumber($_[0], $P, 1);
                if($Num ne "0") {
                    last;
                }
            }
        }
        if($Num eq "0") {
            $Num = $_[0];
        }
        return $Num;
    }
    return $_[0];
}

sub cutNumber($$$)
{
    my ($num, $digs_to_cut, $z) = @_;
    if($num!~/\./)
    {
        $num .= ".";
        foreach (1 .. $digs_to_cut-1) {
            $num .= "0";
        }
    }
    elsif($num=~/\.(.+)\Z/ and length($1)<$digs_to_cut-1)
    {
        foreach (1 .. $digs_to_cut - 1 - length($1)) {
            $num .= "0";
        }
    }
    elsif($num=~/\d+\.(\d){$digs_to_cut,}/) {
      $num=sprintf("%.".($digs_to_cut-1)."f", $num);
    }
    $num=~s/\.[0]+\Z//g;
    if($z) {
        $num=~s/(\.[1-9]+)[0]+\Z/$1/g;
    }
    return $num;
}

sub getSummary()
{
    my $TestInfo = "<h2>Test Info</h2><hr/>\n";
    $TestInfo .= "<table class='summary highlight'>\n";
    
    if(not $CompareDirs or $TargetName)
    {
        if($CheckMode eq "Group") {
            $TestInfo .= "<tr><th class='left'>Group Name</th><td>".$Group{"Name"}."</td></tr>\n";
        }
        else {
            $TestInfo .= "<tr><th class='left'>Package Name</th><td>".getTitle()."</td></tr>\n";
        }
    }
    
    if(not $CompareDirs)
    {
        my @Formats = sort keys(%{$Group{"Format"}});
        $TestInfo .= "<tr><th class='left'>Package Format</th><td>".join(", ", @Formats)."</td></tr>\n";
        if($Group{"Arch"}) {
            $TestInfo .= "<tr><th class='left'>Package Arch</th><td>".$Group{"Arch"}."</td></tr>\n";
        }
    }
    
    $TestInfo .= "<tr><th class='left'>Version #1</th><td>".$Group{"V1"}."</td></tr>\n";
    $TestInfo .= "<tr><th class='left'>Version #2</th><td>".$Group{"V2"}."</td></tr>\n";
    if($QuickMode) {
        $TestInfo .= "<tr><th class='left'>Mode</th><td>Quick</td></tr>\n";
    }
    $TestInfo .= "</table>\n";

    my $TestResults = "<h2>Test Results</h2><hr/>\n";
    $TestResults .= "<table class='summary highlight'>\n";
    
    if(not $CompareDirs)
    {
        my $Packages_Link = "0";
        my %TotalPackages = map {$_=>1} (keys(%{$TargetPackages{1}}), keys(%{$TargetPackages{2}}));
        if(keys(%TotalPackages)>0) {
            $Packages_Link = "<a href='#Packages' style='color:Blue;'>".keys(%TotalPackages)."</a>";
        }
        $TestResults .= "<tr><th class='left'>Total Packages</th><td>".$Packages_Link."</td></tr>\n";
    }
    
    my $Deps_Link = "0";
    if(keys(%TotalDeps)>0) {
        $Deps_Link = "<a href='#Deps' style='color:Blue;'>".keys(%TotalDeps)."</a>";
    }
    if($Group{"Format"}{"DEB"} or $Group{"Format"}{"RPM"} or $Group{"Format"}{"SRPM"}) {
        $TestResults .= "<tr><th class='left'>Total Dependencies</th><td>".$Deps_Link."</td></tr>\n";
    }
    
    my $Files_Link = "0";
    my %TotalFiles = map {$_=>1} (keys(%{$PackageFiles{1}}), keys(%{$PackageFiles{2}}));
    if(keys(%TotalFiles)>0) {
        $Files_Link = "<a href='#Files' style='color:Blue;'>".keys(%TotalFiles)."</a>";
    }
    $TestResults .= "<tr><th class='left'>Total Files</th><td>".$Files_Link."</td></tr>\n";

    if(my $UsedBy = keys(%TotalUsage)) {
        $TestResults .= "<tr><th class='left'>Usage In Other<br/>Packages</th><td><a href='#Usage'>$UsedBy</a></td></tr>\n";
    }
    
    my ($TotalChanged, $Total) = (0, 0);
    # Files
    foreach my $Format (sort keys(%FileChanges))
    {
        $TotalChanged += $FileChanges{$Format}{"SizeDelta"};
        $Total += $FileChanges{$Format}{"Size"};
    }
    # Deps
    foreach my $Kind (keys(%DepChanges))
    {
        $TotalChanged += $DepChanges{$Kind}{"SizeDelta"};
        $Total += $DepChanges{$Kind}{"Size"};
    }
    # Info
    $TotalChanged += $InfoChanges{"SizeDelta"};
    $Total += $InfoChanges{"Size"};
    
    my $Affected = 0;
    if($Total) {
        $Affected = 100*$TotalChanged/$Total;
    }
    $Affected = showNumber($Affected);
    if($Affected>=100) {
        $Affected = 100;
    }
    $RESULT{"affected"} = $Affected;
    
    my $Verdict = "";
    if($TotalChanged)
    {
        $Verdict = "<span style='color:Red;'><b>Changed<br/>(".$Affected."%)</b></span>";
        $RESULT{"status"} = "Changed";
    }
    else
    {
        $Verdict = "<span style='color:Green;'><b>Unchanged</b></span>";
        $RESULT{"status"} = "Unchanged";
    }
    $TestResults .= "<tr><th class='left'>Verdict</th><td>$Verdict</td></tr>\n";
    $TestResults .= "</table>\n";
    
    if(defined $ABI_Change{"Total"})
    {
        $TestResults .= "<h2>ABI Status</h2><hr/>\n";
        $TestResults .= "<table class='summary highlight'>\n";
        $TestResults .= "<tr><th class='left'>Total Objects<br/>(with debug-info)</th><td>".$ABI_Change{"Total"}."</td></tr>\n";
        my $Status = $ABI_Change{"Bin"}/$ABI_Change{"Total"};
        if($Status==100) {
            $TestResults .= "<tr><th class='left'>ABI Compatibility</th><td><span style='color:Green;'><b>100%</b></span></td></tr>\n";
        }
        else {
            $TestResults .= "<tr><th class='left'>ABI Compatibility</th><td><span style='color:Red;'><b>".showNumber(100-$Status)."%</b></span></td></tr>\n";
        }
        $TestResults .= "</table>\n";
    }
    
    my $FileChgs = "<a name='Files'></a><h2>Changes In Files</h2><hr/>\n";
    
    if(keys(%TotalFiles))
    {
        $FileChgs .= "<table class='summary highlight'>\n";
        $FileChgs .= "<tr>";
        $FileChgs .= "<th>File Type</th>";
        $FileChgs .= "<th>Total</th>";
        $FileChgs .= "<th>Added</th>";
        $FileChgs .= "<th>Removed</th>";
        $FileChgs .= "<th>Changed</th>";
        $FileChgs .= "</tr>\n";
        foreach my $Format (sort {$FormatInfo{$b}{"Weight"}<=>$FormatInfo{$a}{"Weight"}}
        sort {lc($FormatInfo{$a}{"Summary"}) cmp lc($FormatInfo{$b}{"Summary"})} keys(%FormatInfo))
        {
            my $Total = $FileChanges{$Format}{"Total"};
            
            if($HideUnchanged) {
                $Total = $FileChanges{$Format}{"Added"} + $FileChanges{$Format}{"Removed"} + $FileChanges{$Format}{"Changed"};
            }
            
            if(not $Total) {
                next;
            }
            
            if($HideUnchanged)
            {
                if(not $Total)
                { # do not show unchanged files
                    next;
                }
                
                $FileChanges{$Format}{"Total"} = $Total;
            }
            
            $FileChgs .= "<tr>\n";
            $FileChgs .= "<td class='left'>".$FormatInfo{$Format}{"Summary"}."</td>\n";
            foreach ("Total", "Added", "Removed", "Changed")
            {
                if($FileChanges{$Format}{$_}>0)
                {
                    my $Link = "<a href='#".$FormatInfo{$Format}{"Anchor"}."' style='color:Blue;'>".$FileChanges{$Format}{$_}."</a>";
                    if($_ eq "Added") {
                        $FileChgs .= "<td class='new'>".$Link."</td>\n";
                    }
                    elsif($_ eq "Removed") {
                        $FileChgs .= "<td class='failed'>".$Link."</td>\n";
                    }
                    elsif($_ eq "Changed") {
                        $FileChgs .= "<td class='warning'>".$Link."</td>\n";
                    }
                    else {
                        $FileChgs .= "<td>".$Link."</td>\n";
                    }
                }
                else {
                    $FileChgs .= "<td>0</td>\n";
                }
            }
            $FileChgs .= "</tr>\n";
        }
        $FileChgs .= "</table>\n";
    }
    else
    {
        $FileChgs .= "No files\n";
    }
    
    return $TestInfo.$TestResults.getReportHeaders().getReportDeps().$FileChgs;
}

sub getSource()
{
    my $Packages = "<a name='Packages'></a>\n";
    my %Pkgs = map {$_=>1} (keys(%{$TargetPackages{1}}), keys(%{$TargetPackages{2}}));
    $Packages .= "<h2>Packages (".keys(%Pkgs).")</h2><hr/>\n";
    $Packages .= "<div class='p_list'>\n";
    foreach my $Name (sort keys(%Pkgs)) {
        $Packages .= $Name."<br/>\n";
    }
    $Packages .= "</div>\n";
    return $Packages;
}

sub createReport($)
{
    my $Path = $_[0];
    my $CssStyles = readModule("Styles", "Index.css");
    my $JScripts = readModule("Scripts", "Sort.js");
    printMsg("INFO", "creating report ...");
    
    my $Title = undef;
    my $Keywords = undef;
    
    if($CompareDirs and not $TargetName)
    {
        $Title = "Changes report between ".$Group{"Name1"}."/ and ".$Group{"Name2"}."/ directories";
        $Keywords = $Group{"Name1"}.", ".$Group{"Name2"}.", changes, report";
    }
    else
    {
        $Title = getTitle().": ".$Group{"V1"}." to ".$Group{"V2"}." changes report";
        $Keywords = getTitle().", changes, report";
    }
    
    my $Header = getHeader();
    my $Description = $Header;
    $Description=~s/<[^<>]+>//g;
    
    my $Report = $Header."\n";
    my $MainReport = getReportFiles();
    
    my $Legend = "<br/><table class='summary highlight'>
    <tr><td class='new' width='80px'>added</td><td class='passed' width='80px'>unchanged</td></tr>
    <tr><td class='warning'>changed</td><td class='failed'>removed</td></tr></table>\n";
    
    $Report .= $Legend;
    $Report .= getSummary();
    $Report .= $MainReport;
    
    if(not $CompareDirs)
    {
        $Report .= getReportUsage();
        $Report .= getSource();
    }
    
    $Report .= "<br/><a class='top_ref' href='#Top'>to the top</a><br/>\n";
    
    $STAT_LINE = "changed:".$RESULT{"affected"}.";".$STAT_LINE."tool_version:".$TOOL_VERSION;
    $Report = "<!-- $STAT_LINE -->\n".composeHTMLHead($Title, $Keywords, $Description, $CssStyles, $JScripts)."\n<body>\n<div><a name='Top'></a>\n".$Report;
    $Report .= "</div>\n<br/><br/><br/><hr/>\n";
    
    # footer
    $Report .= "<div class='footer' style='width:100%;' align='right'><i>Generated";
    $Report .= " by <a href='".$HomePage."'>PkgDiff</a>";
    $Report .= " $TOOL_VERSION &#160;";
    $Report .= "</i></div><br/>\n";
    
    $Report .= "</body></html>";
    writeFile($Path, $Report);
    
    if($RESULT{"status"} eq "Changed") {
        printMsg("INFO", "result: CHANGED (".$RESULT{"affected"}."%)");
    }
    else {
        printMsg("INFO", "result: UNCHANGED");
    }
    
    printMsg("INFO", "report: $Path");
}

sub checkCmd($)
{
    my $Cmd = $_[0];
    
    if(defined $Cache{"checkCmd"}{$Cmd}) {
        return $Cache{"checkCmd"}{$Cmd};
    }
    foreach my $Path (sort {length($a)<=>length($b)} split(/:/, $ENV{"PATH"}))
    {
        if(-x $Path."/".$Cmd) {
            return ($Cache{"checkCmd"}{$Cmd} = 1);
        }
    }
    return ($Cache{"checkCmd"}{$Cmd} = 0);
}

sub readFileTypes()
{
    my $FileTypes = readFile($MODULES_DIR."/FileType.xml");
    while(my $FileType = parseTag(\$FileTypes, "type"))
    {
        my $ID = parseTag(\$FileType, "id");
        if(not $ID) {
            next;
        }
        $FormatInfo{$ID}{"ID"} = $ID;
        if(my $Summary = parseTag(\$FileType, "summary")) {
            $FormatInfo{$ID}{"Summary"} = $Summary;
        }
        if(my $Title = parseTag(\$FileType, "title")) {
            $FormatInfo{$ID}{"Title"} = $Title;
        }
        $FormatInfo{$ID}{"Weight"} = parseTag(\$FileType, "weight");
        if(my $Anchor = parseTag(\$FileType, "anchor")) {
            $FormatInfo{$ID}{"Anchor"} = $Anchor;
        }
        if(my $Format = parseTag(\$FileType, "format")) {
            $FormatInfo{$ID}{"Format"} = $Format;
        }
        foreach my $Ext (split(/\s*(\n|,)\s*/, parseTag(\$FileType, "extensions")))
        {
            $FormatInfo{$ID}{"Ext"}{$Ext} = 1;
            $FileFormat{"Ext"}{$Ext} = $ID;
        }
        foreach my $Ext (split(/\s*(\n|,)\s*/, parseTag(\$FileType, "iextensions")))
        {
            $FormatInfo{$ID}{"iExt"}{lc($Ext)} = 1;
            $FileFormat{"iExt"}{lc($Ext)} = $ID;
        }
        foreach my $Name (split(/\s*(\n|,)\s*/, parseTag(\$FileType, "names")))
        {
            $FormatInfo{$ID}{"Name"}{$Name} = 1;
            $FileFormat{"Name"}{$Name} = $ID;
        }
        foreach my $Name (split(/\s*(\n|,)\s*/, parseTag(\$FileType, "inames")))
        {
            $FormatInfo{$ID}{"iName"}{lc($Name)} = 1;
            $FileFormat{"iName"}{lc($Name)} = $ID;
        }
        foreach my $Term (split(/\s*(\n|,)\s*/, parseTag(\$FileType, "terms")))
        {
            $Term=~s/\s+/_/g;
            $TermFormat{uc($Term)} = $ID;
        }
        foreach my $Dir (split(/\s*(\n|,)\s*/, parseTag(\$FileType, "dirs")))
        {
            $DirFormat{$Dir} = $ID;
        }
        foreach my $Bytes (split(/\s*(\n|,)\s*/, parseTag(\$FileType, "bytes")))
        {
            $BytesFormat{$Bytes} = $ID;
        }
    }
    foreach my $Format (keys(%FormatInfo))
    {
        if(not $FormatInfo{$Format}{"Title"}) {
            $FormatInfo{$Format}{"Title"} = autoTitle($FormatInfo{$Format}{"Summary"});
        }
        if(not $FormatInfo{$Format}{"Anchor"}) {
            $FormatInfo{$Format}{"Anchor"} = autoAnchor($FormatInfo{$Format}{"Title"});
        }
    }
}

sub autoTitle($)
{
    my $Summary = $_[0];
    my $Title = $Summary;
    while($Title=~/ ([a-z]+)/)
    {
        my ($W, $UW) = ($1, ucfirst($1));
        $Title=~s/ $W/ $UW/g;
    }
    if($Title!~/data\Z/i)
    {
        if(not $Title=~s/y\Z/ies/)
        { # scripts, files, libraries
            if(not $Title=~s/ss\Z/sses/)
            { # classes
                if(not $Title=~s/ch\Z/ches/)
                { # patches
                    $Title .= "s";
                }
            }
        }
    }
    return $Title;
}

sub autoAnchor($)
{
    my $Title = $_[0];
    my $Anchor = $Title;
    $Anchor=~s/\+\+/PP/g;
    $Anchor=~s/C#/CS/g;
    $Anchor=~s/\W//g;
    return $Anchor;
}

sub getDumpversion($)
{
    my $Cmd = $_[0];
    return `$Cmd -dumpversion 2>$TMP_DIR/null`;
}

sub cmpVersions($$)
{ # compare two versions in dotted-numeric format
    my ($V1, $V2) = @_;
    return 0 if($V1 eq $V2);
    return undef if($V1!~/\A\d+[\.\d+]*\Z/);
    return undef if($V2!~/\A\d+[\.\d+]*\Z/);
    my @V1Parts = split(/\./, $V1);
    my @V2Parts = split(/\./, $V2);
    for (my $i = 0; $i <= $#V1Parts && $i <= $#V2Parts; $i++) {
        return -1 if(int($V1Parts[$i]) < int($V2Parts[$i]));
        return 1 if(int($V1Parts[$i]) > int($V2Parts[$i]));
    }
    return -1 if($#V1Parts < $#V2Parts);
    return 1 if($#V1Parts > $#V2Parts);
    return 0;
}

sub getArchivePattern()
{
    my @Groups = ();
    foreach (sort {length($b)<=>length($a)} keys(%ArchiveFormats))
    {
        my @Fmts = @{$ArchiveFormats{$_}};
        $ArchiveFormats{$_} = join("|", @Fmts);
        $ArchiveFormats{$_}=~s/\./\\./g;
        push(@Groups, $ArchiveFormats{$_});
    }
    return join("|", @Groups);
}

sub encodeUrl($)
{
    my $Url = $_[0];
    $Url=~s/#/\%23/g;
    return $Url;
}

sub scenario()
{
    if($Help)
    {
        helpMsg();
        exit(0);
    }
    if($ShowVersion)
    {
        printMsg("INFO", "Package Changes Analyzer (PkgDiff) $TOOL_VERSION\nCopyright (C) 2018 Andrey Ponomarenko's ABI Laboratory\nLicense: GNU GPL <http://www.gnu.org/licenses/>\nThis program is free software: you can redistribute it and/or modify it.\n\nWritten by Andrey Ponomarenko.");
        exit(0);
    }
    if($DumpVersion)
    {
        printMsg("INFO", $TOOL_VERSION);
        exit(0);
    }
    if($GenerateTemplate)
    {
        generateTemplate();
        exit(0);
    }
    
    if(checkModule("File/LibMagic.pm"))
    {
        $USE_LIBMAGIC = 1;
        require File::LibMagic;
    }
    else {
        printMsg("WARNING", "perl-File-LibMagic is not installed");
    }
    
    if(not $DiffWidth) {
        $DiffWidth = $DEFAULT_WIDTH;
    }
    if(not $DiffLines) {
        $DiffLines = $DIFF_PRE_LINES;
    }
    if($CheckUsage)
    {
        if(not $PackageManager) {
            exitStatus("Error", "-pkg-manager option is not specified");
        }
    }
    if(not -f $DIFF) {
        exitStatus("Not_Found", "can't access \"$DIFF\"");
    }
    
    if(not checkCmd("wdiff")) {
        print STDERR "WARNING: wdiff is not installed\n";
    }
    
    if(not $LinksTarget)
    {
        $LinksTarget = "_self";
    }
    else
    {
        if($LinksTarget!~/\A(_blank|_self)\Z/)
        {
            exitStatus("Error", "incorrect value of links target");
        }
    }
    
    if($ShowDetails)
    {
        if(my $V = getDumpversion($ACC))
        {
            if(cmpVersions($V, $ACC_VER)==-1)
            {
                printMsg("ERROR", "the version of ABI Compliance Checker should be $ACC_VER or newer");
                $ACC = undef;
            }
        }
        else
        {
            printMsg("ERROR", "cannot find ABI Compliance Checker");
            $ACC = undef;
        }
        
        if(my $V = getDumpversion($ABI_DUMPER))
        {
            if(cmpVersions($V, $ABI_DUMPER_VER)==-1)
            {
                printMsg("ERROR", "the version of ABI Dumper should be $ABI_DUMPER_VER or newer");
                $ABI_DUMPER = undef;
            }
        }
        else
        {
            printMsg("ERROR", "cannot find ABI Dumper");
            $ABI_DUMPER = undef;
        }
    }
    if(not $Descriptor{1}) {
        exitStatus("Error", "-old option is not specified");
    }
    
    if(not $Descriptor{2}) {
        exitStatus("Error", "-new option is not specified");
    }
    
    
    if($CompareDirs)
    {
        if(not -d $Descriptor{1}) {
            exitStatus("Access_Error", "can't access directory \'".$Descriptor{1}."\'");
        }
        if(not -d $Descriptor{2}) {
            exitStatus("Access_Error", "can't access directory \'".$Descriptor{2}."\'");
        }
        $Descriptor{1} = getAbsPath($Descriptor{1});
        $Descriptor{2} = getAbsPath($Descriptor{2});
    }
    else
    {
        if(not -f $Descriptor{1}) {
            exitStatus("Access_Error", "can't access file \'".$Descriptor{1}."\'");
        }
        if(not -f $Descriptor{2}) {
            exitStatus("Access_Error", "can't access file \'".$Descriptor{2}."\'");
        }
    }
    
    readFileTypes();
    
    if($CompareDirs) {
        printMsg("INFO", "Reading directories ...");
    }
    else {
        printMsg("INFO", "Reading packages ...");
    }
    
    my $Fmt1 = getFormat($Descriptor{1});
    my $Fmt2 = getFormat($Descriptor{2});
    
    my ($Ph1, $Ph2) = ();
    
    if($CompareDirs and $Fmt1 eq "DIR")
    {
        $RemovePrefix{1} = getDirname($Descriptor{1});
        $RemovePrefix{2} = getDirname($Descriptor{2});
    }
    elsif($Fmt1 eq "ARCHIVE" and $Fmt2 eq "ARCHIVE")
    { # check if we can remove a common prefix from files of BOTH packages
        ($Ph1->{"CPath"}, $Ph1->{"Attr"}) = readPackage($Descriptor{1}, 1);
        ($Ph2->{"CPath"}, $Ph2->{"Attr"}) = readPackage($Descriptor{2}, 2);
        
        my @Cnt1 = listDir($Ph1->{"CPath"});
        my @Cnt2 = listDir($Ph2->{"CPath"});
        if($#Cnt1==0 and $#Cnt2==0)
        {
            if(-d $Ph1->{"CPath"}."/".$Cnt1[0] and -d $Ph2->{"CPath"}."/".$Cnt2[0])
            {
                $RemovePrefix{1} = $Cnt1[0];
                $RemovePrefix{2} = $Cnt2[0];
            }
        }
    }
    
    if($CompareDirs and $Fmt1 eq "DIR")
    {
        registerPackage($Descriptor{1}, 1);
        $Group{"Name1"} = getFilename($Descriptor{1});
        if($TargetVersion{1}) {
            $Group{"V1"} = $TargetVersion{1};
        }
        else {
            $Group{"V1"} = "X";
        }
    }
    elsif($Fmt1=~/\A(RPM|SRPM|DEB|ARCHIVE)\Z/)
    {
        my $Attr = registerPackage($Descriptor{1}, 1, $Ph1);
        $Group{"Name1"} = $Attr->{"Name"};
        $Group{"V1"} = $Attr->{"Version"};
        $Group{"Arch1"} = $Attr->{"Arch"};
        
        if(defined $TargetVersion{1}) {
            $Group{"V1"} = $TargetVersion{1};
        }
    }
    else
    {
        if($Descriptor{1}=~/\.(\w+)\Z/)
        {
            if($1 ne "xml") {
                exitStatus("Error", "unknown format \"$1\"");
            }
        }
        readDescriptor(1, $Descriptor{1});
    }
    
    if($CompareDirs and $Fmt1 eq "DIR")
    {
        registerPackage($Descriptor{2}, 2);
        $Group{"Name2"} = getFilename($Descriptor{2});
        if($TargetVersion{2}) {
            $Group{"V2"} = $TargetVersion{2};
        }
        else {
            $Group{"V2"} = "Y";
        }
    }
    elsif($Fmt2=~/\A(RPM|SRPM|DEB|ARCHIVE)\Z/)
    {
        my $Attr = registerPackage($Descriptor{2}, 2, $Ph2);
        $Group{"Name2"} = $Attr->{"Name"};
        $Group{"V2"} = $Attr->{"Version"};
        $Group{"Arch2"} = $Attr->{"Arch"};
        
        if(defined $TargetVersion{2}) {
            $Group{"V2"} = $TargetVersion{2};
        }
    }
    else
    {
        if($Descriptor{2}=~/\.(\w+)\Z/)
        {
            if($1 ne "xml") {
                exitStatus("Error", "unknown format \"$1\"");
            }
        }
        readDescriptor(2, $Descriptor{2});
    }
    if($Group{"Count1"}>1
    or $Group{"Count2"}>1) {
        $CheckMode = "Group";
    }
    
    if($CompareDirs)
    {
        if($TargetName)
        {
            $Group{"Name"} = $TargetName;
        }
    }
    else
    {
        $Group{"Name"} = $Group{"Name1"};
        if($Group{"Name1"} ne $Group{"Name2"})
        {
            if($CheckMode eq "Group") {
                printMsg("WARNING", "different group names in descriptors (\"".$Group{"Name1"}."\" and \"".$Group{"Name2"}."\")");
            }
            else {
                printMsg("WARNING", "different package names (\"".$Group{"Name1"}."\" and \"".$Group{"Name2"}."\")");
            }
        }
    }
    if($Group{"Count1"} ne $Group{"Count2"}) {
        printMsg("WARNING", "different number of packages in descriptors");
    }
    if(defined $Group{"Arch1"} and defined $Group{"Arch2"})
    {
        $Group{"Arch"} = $Group{"Arch1"};
        if($Group{"Arch1"} ne $Group{"Arch2"}) {
            printMsg("WARNING", "different architectures of packages (\"".$Group{"Arch1"}."\" and \"".$Group{"Arch2"}."\")");
        }
    }
    if(defined $Group{"Format"}{"DEB"}
    and defined $Group{"Format"}{"RPM"}) {
        printMsg("WARNING", "incompatible package formats: RPM and DEB");
    }
    if($OutputReportPath)
    { # user-defined path
        $REPORT_PATH = $OutputReportPath;
        $REPORT_DIR = getDirname($REPORT_PATH);
        if(not $REPORT_DIR) {
            $REPORT_DIR = ".";
        }
    }
    else
    {
        if($CompareDirs and not $TargetName)
        {
            $REPORT_DIR = "pkgdiff_reports/".$Group{"Name1"}."_to_".$Group{"Name2"};
        }
        else
        {
            $REPORT_DIR = "pkgdiff_reports/".$Group{"Name"}."/".$Group{"V1"}."_to_".$Group{"V2"};
        }
        $REPORT_PATH = $REPORT_DIR."/changes_report.html";
        if(-d $REPORT_DIR)
        {
            foreach my $E ("info-diffs", "diffs", "details") {
                rmtree($REPORT_DIR."/".$E);
            }
        }
    }
    
    if($CompareDirs) {
        printMsg("INFO", "Comparing directories ...");
    }
    else {
        printMsg("INFO", "Comparing packages ...");
    }
    
    detectChanges();
    createReport($REPORT_PATH);
    
    foreach my $E ("info-diffs", "diffs", "details")
    {
        if(not listDir($REPORT_DIR."/".$E)) {
            rmtree($REPORT_DIR."/".$E);
        }
    }
    
    if($ExtraInfo) {
        writeExtraInfo();
    }
    
    if($CustomTmpDir) {
        cleanTmp();
    }
    
    exit($ERROR_CODE{$RESULT{"status"}});
}

scenario();
