#!/usr/bin/perl
###########################################################################
# pkgdiff - Package Changes Analyzer 1.3.2
# A tool for analyzing changes in Linux software packages
#
# Copyright (C) 2011-2012 ROSA Laboratory.
#
# Written by Andrey Ponomarenko
#
# PLATFORMS
# =========
#  GNU/Linux, FreeBSD
#
# PACKAGE FORMATS
# ===============
#  RPM, DEB, TAR.GZ, etc.
#
# REQUIREMENTS
# ============
#  Perl 5 (5.8-5.14)
#  GNU Binutils (readelf)
#  GNU Diff, Wdiff
#  GNU Awk
#  RPM (rpm, rpmbuild, rpm2cpio) for analysis of RPM-packages
#  DPKG (dpkg, dpkg-deb) for analysis of DEB-packages
#
# SUGGESTIONS
# ===========
#  ABI Compliance Checker (>=1.96.7)
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
use Getopt::Long;
Getopt::Long::Configure ("posix_default", "no_ignore_case");
use File::Path qw(mkpath rmtree);
use File::Temp qw(tempdir);
use File::Compare;
use Cwd qw(abs_path cwd);

my $TOOL_VERSION = "1.3.2";
my $ORIG_DIR = cwd();
my $TMP_DIR = tempdir(CLEANUP=>1);

# Internal modules
my $MODULES_DIR = get_Modules();
push(@INC, get_dirname($MODULES_DIR));

my $DIFF = $MODULES_DIR."/Internals/Tools/rfcdiff-1.41-ROSA.sh";
my $ABICC = "abi-compliance-checker";

my ($Help, $ShowVersion, $DumpVersion, $GenerateTemplate, %Descriptor,
$CheckUsage, $PackageManager, $OutputReportPath, $ShowDetails, $Debug,
$SizeLimit, $QuickMode, $DiffWidth, $DiffLines, $Browse, $Minimal,
$IgnoreSpaceChange, $IgnoreAllSpace, $IgnoreBlankLines);

my $CmdName = get_filename($0);

my %ERROR_CODE = (
    # Compatible verdict
    "Compatible"=>0,
    "Success"=>0,
    # Incompatible verdict
    "Incompatible"=>1,
    # Undifferentiated error code
    "Error"=>2,
    # System command is not found
    "Not_Found"=>3,
    # Cannot access input files
    "Access_Error"=>4,
    # Cannot find a module
    "Module_Error"=>9
);

my %HomePage = (
    "Dev"=>"http://pkgdiff.github.com/pkgdiff/"
);

my $ShortUsage = "Package Changes Analyzer (pkgdiff) $TOOL_VERSION
A tool for analyzing changes in Linux software packages
Copyright (C) 2012 ROSA Laboratory
License: GNU GPL

Usage: $CmdName [options]
Example: $CmdName -old OLD.rpm -new NEW.rpm

More info: $CmdName --help\n";

if($#ARGV==-1) {
    printMsg("INFO", $ShortUsage);
    exit(0);
}

foreach (2 .. $#ARGV)
{ # correct comma separated options
    if($ARGV[$_-1] eq ",") {
        $ARGV[$_-2].=",".$ARGV[$_];
        splice(@ARGV, $_-1, 2);
    }
    elsif($ARGV[$_-1]=~/,\Z/) {
        $ARGV[$_-1].=$ARGV[$_];
        splice(@ARGV, $_, 1);
    }
    elsif($ARGV[$_]=~/\A,/
    and $ARGV[$_] ne ",") {
        $ARGV[$_-1].=$ARGV[$_];
        splice(@ARGV, $_, 1);
    }
}

GetOptions("h|help!" => \$Help,
  "v|version!" => \$ShowVersion,
  "dumpversion!" => \$DumpVersion,
# general options
  "old=s" => \$Descriptor{1},
  "new=s" => \$Descriptor{2},
# other options
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
  "browse=s" => \$Browse,
  "debug!" => \$Debug
) or ERR_MESSAGE();

sub ERR_MESSAGE()
{
    printMsg("INFO", "\n".$ShortUsage);
    exit($ERROR_CODE{"Error"});
}

my $HelpMessage="
NAME:
  Package Changes Analyzer ($CmdName)
  A tool for analyzing changes in Linux software packages

DESCRIPTION:
  Package Changes Analyzer (pkgdiff) is a tool for analyzing
  changes in Linux software packages (RPM, DEB, TAR.GZ, etc).

  The tool is intended for Linux maintainers who are interested
  in ensuring compatibility of old and new versions of packages.

  This tool is free software: you can redistribute it and/or
  modify it under the terms of the GNU GPL.

USAGE:
  $CmdName [options]

EXAMPLE:
  $CmdName -old OLD.rpm -new NEW.rpm

INFORMATION OPTIONS:
  -h|-help
      Print this help.

  -v|-version
      Print version information.

  -dumpversion
      Print the tool version ($TOOL_VERSION) and don't do anything else.

GENERAL OPTIONS:
  -old PATH
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

  -new PATH
      Path to the new version of a package (RPM, DEB, TAR.GZ, etc).

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

  -report-path PATH
      Path to the report.
      Default:
        pkgdiff_reports/<pkg>/<v1>_to_<v2>/compat_report.html

  -details
      Try to create detailed reports.

  -size-limit SIZE
      Don't analyze files larger than <size> in kilobytes.

  -width <size>
      Width of Visual Diff.
      Default: 75

  -prelines NUM
      Size of the context in Visual Diff.
      Default: 10

  -ignore-space-change
      Ignore changes in the amount of white space.

  -ignore-all-space
      Ignore all white space.

  -ignore-blank-lines
      Ignore changes whose lines are all blank.

  -quick
      Quick mode without creating of Visual Diff for files.

  -minimal
      Try to find a smaller set of changes.

  -browse PROGRAM
      Open report(s) in the browser (firefox, opera, etc.).

  -debug
      Show debug info.

REPORT:
    Report will be generated to:
        pkgdiff_reports/<pkg>/<v1>_to_<v2>/compat_report.html

EXIT CODES:
    0 - Compatible. The tool has run without any errors.
    non-zero - Incompatible or the tool has run with errors.

REPORT BUGS TO:
    Andrey Ponomarenko <aponomarenko\@mandriva.org>

MORE INFORMATION:
    ".$HomePage{"Dev"}."\n";

sub HELP_MESSAGE() {
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
my $DEFAULT_WIDTH = 75;
my $DIFF_PRE_LINES = 10;

my %Group = (
    "Count1"=>0,
    "Count2"=>0
);

my %FormatInfo = ();
my %FileFormat = ();
my %TermFormat = ();

# Cache
my %Cache;

# Modes
my $CheckMode = "Single";

# Packages
my %TargetPackages;
my %PackageFiles;
my %FileChanges;
my %PackageInfo;
my %InfoChanges;
my %FileGroup;
my %PackageUsage;
my %TotalUsage;

# Deps
my %PackageDeps;
my %TotalDeps;
my %DepChanges;

# Files
my %AddedFiles;
my %RemovedFiles;
my %StableFiles;
my %RenamedFiles;
my %RenamedFiles_R;
my %MovedFiles;
my %MovedFiles_R;
my %SkipFiles;
my %FormatFiles;

# Report
my $REPORT_PATH;
my $REPORT_DIR;
my %RESULT;

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
                   "ear"]
);

my $ARCHIVE_EXT = getArchivePattern();

sub get_Modules()
{
    my $TOOL_DIR = get_dirname($0);
    if(not $TOOL_DIR) {
        $TOOL_DIR = ".";
    }
    my @SEARCH_DIRS = (
        # tool's directory
        abs_path($TOOL_DIR),
        # relative path to modules
        abs_path($TOOL_DIR)."/../share/pkgdiff",
        # system directory
        "MODULES_INSTALL_PATH"
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

sub readStyles($)
{
    my $Name = $_[0];
    my $Path = $MODULES_DIR."/Internals/Styles/".$Name;
    if(not -f $Path) {
        exitStatus("Module_Error", "can't access \'$Path\'");
    }
    my $Styles = readFile($Path);
    return "<style type=\"text/css\">\n".$Styles."\n</style>";
}

sub compareFiles($$$$)
{
    my ($P1, $P2, $N1, $N2) = @_;
    if(not -f $P1
    or not -f $P2)
    {
        if(not -l $P1)
        { # broken symlinks
            return ();
        }
    }
    my $Format = getFormat($P1);
    if($Format ne getFormat($P2)) {
        return ();
    }
    if(getSize($P1) == getSize($P2))
    { # equal size
        if(compare($P1, $P2)==0)
        { # equal content
            return (-1, "", "", 0);
        }
    }
    if($QuickMode)
    { # --quick
        return (3, "", "", 1);
    }
    if(skip_file($P1, 1))
    { # <skip_files>
        return (2, "", "", 1);
    }
    if(defined $SizeLimit)
    {
        if(getSize($P1) > $SizeLimit*1024
        or getSize($P2) > $SizeLimit*1024)
        {
            return (2, "", "", 1);
        }
    }
    my ($Changed, $DLink, $Rate, $RLink) = ();
    
    if($FormatInfo{$Format}{"Format"} eq "Text") {
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
        }
        else
        { 
            ($DLink, $Rate) = diffFiles($P1, $P2, getRPath("diffs", $N1));
        }
    }
    elsif($Format eq "SHARED_OBJECT"
    or $Format eq "STATIC_LIBRARY"
    or $Format eq "COMPILED_OBJECT"
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
            if(readFile($Page1) eq readFile($Page2)) {
                return ();
            }
        }
        ($DLink, $Rate) = diffFiles($Page1, $Page2, getRPath("diffs", $N1));
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
            if($ABICC)
            {
                if($Format eq "SHARED_OBJECT"
                or $Format eq "STATIC_LIBRARY"
                or $Format eq "HEADER") {
                    $RLink = runABICC(getRPath("details", "abi"));
                }
            }
        }
        $DLink =~s/\A\Q$REPORT_DIR\E\///;
        $RLink =~s/\A\Q$REPORT_DIR\E\///;
        return (1, $DLink, $RLink, $Rate);
    }
    else {
        return ();
    }
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
    if($Rate*($Size1 + $Size2)/2<1024)
    {
        if(-T $P1)
        { # Text
            my $TDiff = $TMP_DIR."/txtdiff";
            system("diff -Bw \"$P1\" \"$P2\" >$TDiff 2>$TMP_DIR/null");
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
            system("diff -Bw \"$T1\" \"$T2\" >$TDiff 2>$TMP_DIR/null");
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
    my ($Dir, $Name) = separate_path($Path);
    my $Cmd = "";
    if($Format eq "MANPAGE")
    {
        $Name=~s/\.(gz|bz2|xz)\Z//;
        $Cmd = "man $Path|col -bfx";
    }
    elsif($Format eq "INFODOC")
    {
        $Name=~s/\.(gz|bz2|xz)\Z//;
        $Path=~s/\.(gz|bz2|xz)\Z//;
        $Cmd = "info $Path";
    }
    elsif($Format eq "ARCHIVE")
    {
        my $Unpack = $TMP_DIR."/unpack/";
        rmtree($Unpack);
        unpackArchive($Path, $Unpack);
        my @Contents = listDir($Unpack);
        if($#Contents==0) {
            $Cmd = "cat $Unpack/".$Contents[0];
        }
        else {
            return "";
        }
    }
    elsif($Format eq "SHARED_OBJECT"
    or $Format eq "EXE"
    or $Format eq "COMPILED_OBJECT"
    or $Format eq "STATIC_LIBRARY")
    {
        $Cmd = "readelf -Wa $Path";
    }
    elsif($Format eq "SYMLINK")
    {
        $Cmd = "file -b $Path";
    }
    elsif($Format eq "JAVA_CLASS")
    {
        if(not checkCmd("javap")) {
            return "";
        }
        $Name=~s/\.class\Z//;
        $Name=~s/\$/./;
        $Path = $Name;
        $Cmd = "javap $Path"; # -s -c -private -verbose
        chdir($Dir);
    }
    my $SPath = $TMP_DIR."/".$Format."/".$Version."/".$Name;
    mkpath(get_dirname($SPath));
    system($Cmd." >".$SPath." 2>$TMP_DIR/null");
    if($Format eq "JAVA_CLASS") {
        chdir($ORIG_DIR);
    }
    if($Format eq "SHARED_OBJECT"
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

sub runABICC($)
{
    my $Path = $_[0];
    if(defined $Cache{"runABICC"}) {
        return $Cache{"runABICC"};
    }
    mkpath(get_dirname($Path));
    my $D1P = $TMP_DIR."/desc/1.xml";
    my $D2P = $TMP_DIR."/desc/2.xml";
    my $Cmd = $ABICC." -d1 $D1P -d2 $D2P";
    $Cmd .= " -l ".$Group{"Name"};
    my @L1 = keys(%{$FormatFiles{"1"}{"SHARED_OBJECT"}});
    my @L2 = keys(%{$FormatFiles{"2"}{"SHARED_OBJECT"}});
    my @SL1 = keys(%{$FormatFiles{"1"}{"STATIC_LIBRARY"}});
    my @SL2 = keys(%{$FormatFiles{"2"}{"STATIC_LIBRARY"}});
    my @H1 = keys(%{$FormatFiles{"1"}{"HEADER"}});
    my @H2 = keys(%{$FormatFiles{"2"}{"HEADER"}});
    if(not @L1 or not @L2)
    {
        if(@SL1 and @SL2)
        { # use static libs
            @L1 = @SL1;
            @L2 = @SL2;
            $Cmd .= " -static";
        }
    }
    if(@L1 and @L2
    and (not @H1 or not @H2))
    {
        $Cmd .= " -objects-only";
    }
    elsif(@H1 and @H2
    and (not @L1 or not @L2))
    {
        $Cmd .= " -headers-only";
    }
    elsif(not @L1 or not @H1
    or not @L2 or not @H2)
    {
        return ($Cache{"runABICC"} = "");
    }
    my $D1 = "
        <version>
            ".$Group{"V1"}."
        </version>
        <libs>
            ".join("\n", @L1)."
        </libs>
        <headers>
            ".join("\n", @H1)."
        </headers>";
    my $D2 = "
        <version>
            ".$Group{"V2"}."
        </version>
        <libs>
            ".join("\n", @L2)."
        </libs>
        <headers>
            ".join("\n", @H2)."
        </headers>";
    writeFile($D1P, $D1);
    writeFile($D2P, $D2);
    my $LogPath = "$REPORT_DIR/logs/abicc-log.txt";
    $Cmd .= " --report-path=$Path";
    $Cmd .= " --log-path=$LogPath";
    $Cmd .= " -quiet";
    printMsg("INFO", "Running ABICC ...");
    system($Cmd);
    my $Ret = $?>>8;
    if($Ret==0 or $Ret==1)
    { # the tool has run without any errors
        return ($Cache{"runABICC"} = $Path);
    }
    else {
        printMsg("WARNING", "Failed to run ABICC, see error log:\n  $LogPath");
    }
    return ($Cache{"runABICC"} = "");
}

sub getLibName($)
{
    my $Name = get_filename($_[0]);
    if($Name=~/\A(.+\.so)/){
        return $1;
    }
    return "";
}

sub getSize($)
{
    if($Cache{"getSize"}{$_[0]}) {
        return $Cache{"getSize"}{$_[0]};
    }
    return ($Cache{"getSize"}{$_[0]} = -s $_[0]);
}

sub diffFiles($$$)
{
    my ($P1, $P2, $Path) = @_;
    if(not $P1 or not $P2) {
        return "";
    }
    mkpath(get_dirname($Path));
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
    $Cmd .= " \"".$P1."\" \"".$P2."\" >\"".$Path."\" 2>$TMP_DIR/null";
    $Cmd=~s/\$/\\\$/g;
    system($Cmd);
    if(getSize($Path)<3500)
    { # may be identical
        if(readFilePart($Path, 2)=~/The files are identical/)
        {
            unlink($Path);
            return "";
        }
    }
    if(getSize($Path)<3100)
    { # may be identical or non-text
        if(readFile($Path)=~/No changes/)
        {
            unlink($Path);
            return "";
        }
    }
    my $Rate = getRate($P1, $P2, $TmpPath);
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
    return "" if(not $Path or not -f $Path);
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
    if(not $Path or not -e $Path) {
        return "";
    }
    if($Cache{"getType"}{$Path}) {
        return $Cache{"getType"}{$Path};
    }
    return ($Cache{"getType"}{$Path} = `file -b \"$Path\"`);
}

sub isRenamed($$$)
{
    my ($P1, $P2, $Match) = @_;
    my ($D1, $N1) = separate_path($P1);
    my ($D2, $N2) = separate_path($P2);
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
    else {
        return $_[1];
    }
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
    my ($D1, $N1) = separate_path($P1);
    my ($D2, $N2) = separate_path($P2);
    if($N1 eq $N2
    and $D1 ne $D2) {
        return 1;
    }
    return 0;
}

sub detectChanges()
{
    mkpath($REPORT_DIR."/diffs");
    mkpath($REPORT_DIR."/info-diffs");
    mkpath($REPORT_DIR."/details");
    foreach my $Format (keys(%FormatInfo))
    {
        %{$FileChanges{$Format}} = (
            "Total"=>0,
            "Added"=>0,
            "Removed"=>0,
            "Changed"=>0
        );
    }
    my (%AddedByDir, %RemovedByDir, %AddedByName,
    %RemovedByName, %AddedByPrefix, %RemovedByPrefix) = ();
    foreach my $Name (sort keys(%{$PackageFiles{1}}))
    { # checking old files
        my $Format = getFormat($PackageFiles{1}{$Name});
        $FormatFiles{1}{$Format}{$PackageFiles{1}{$Name}}=1;
        if(not defined $PackageFiles{2}{$Name})
        { # removed files
            $RemovedFiles{$Name}=1;
            $RemovedByDir{get_dirname($Name)}{$Name}=1;
            $RemovedByName{get_filename($Name)}{$Name}=1;
            if(my $Prefix = get_fileprefix($Name)) {
                $RemovedByPrefix{$Prefix}{$Name}=1;
            }
        }
        else {
            $StableFiles{$Name}=1;
        }
    }
    foreach my $Name (keys(%{$PackageFiles{2}}))
    { # checking new files
        my $Format = getFormat($PackageFiles{2}{$Name});
        $FormatFiles{2}{$Format}{$PackageFiles{2}{$Name}}=1;
        if(not defined $PackageFiles{1}{$Name})
        { # added files
            $AddedFiles{$Name}=1;
            $AddedByDir{get_dirname($Name)}{$Name}=1;
            $AddedByName{get_filename($Name)}{$Name}=1;
            if(my $Prefix = get_fileprefix($Name)) {
                $AddedByPrefix{$Prefix}{$Name}=1;
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
    foreach my $Name (sort keys(%RemovedFiles))
    { # checking moved files
        my $Format = getFormat($PackageFiles{1}{$Name});
        
        my $FileName = get_filename($Name);
        my @Removed = keys(%{$RemovedByName{$FileName}});
        my @Added = keys(%{$AddedByName{$FileName}});
        
        if($#Added!=0 or $#Removed!=0)
        { # one added
          # one removed
            my $Prefix = get_fileprefix($Name);
            my @RemovedPrefix = keys(%{$RemovedByPrefix{$Prefix}});
            my @AddedPrefix = keys(%{$AddedByPrefix{$Prefix}});
            if($#AddedPrefix!=0 or $#RemovedPrefix!=0) {
                next;
            }
            @Added = @AddedPrefix;
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
        my @Removed = keys(%{$RemovedByDir{get_dirname($Name)}});
        my @Added = keys(%{$AddedByDir{get_dirname($Name)}});
        my $Match = 2;
        if($#Removed==0 and $#Added==0) {
            $Match *= 2;
        }
        my $FName = get_filename($Name);
        my $Len = length($FName);
        foreach my $File (sort {getBaseLen($FName, get_filename($b)) <=> getBaseLen($FName, get_filename($a))}
        sort { abs(length(get_filename($a))-$Len) <=> abs(length(get_filename($b))-$Len) } @Added)
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
        my %Details = ();
        my ($Changed, $DLink, $RLink, $Rate) = compareFiles($Path, $NewPath, $Name, $NewName);
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
            }
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
        }
        else
        {
            $Details{"Status"} = "unchanged";
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
}

sub htmlSpecChars($)
{
    my $Str = $_[0];
    $Str=~s/</&lt;/g;
    $Str=~s/>/&gt;/g;
    $Str=~s/\"/&quot;/g;
    $Str=~s/\'/&#39;/g;
    return $Str;
}

sub get_Report_Usage()
{
    if(not keys(%PackageUsage)) {
        return "";
    }
    my $Report = "<a name='Usage'></a>\n";
    $Report .= "<h2>Usage Analysis</h2><hr/>\n";
    $Report .= "<table class='summary'>\n";
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

sub get_Report_Headers()
{
    if(not keys(%PackageInfo)) {
        return "";
    }
    my $Report = "<a name='Info'></a>\n";
    $Report .= "<h2>Changes In Package Info</h2><hr/>\n";
    $Report .= "<table class='summary'>\n";
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
                $Report .= "<td class='value'>".show_number($Details{$Package}{"Rate"}*100)."%</td>\n";
                $Report .= "<td><a href='".$Details{$Package}{"Diff"}."' style='color:Blue;'>diff</a></td>\n";
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

sub get_Report_Deps()
{
    my $Report = "<a name='Deps'></a>\n";
    foreach my $Kind (sort keys(%DepChanges))
    {
        my @Names = keys(%{$DepChanges{$Kind}{"Details"}});
        if(not @Names) {
            next;
        }
        $Report .= "<h2>Changes In \"".ucfirst($Kind)."\" Dependencies</h2><hr/>\n";
        $Report .= "<table class='summary'>\n";
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

sub divideStr($)
{
    my $Str = $_[0];
    my $MAXLENGTH = 99;
    if(length($Str)>$MAXLENGTH)
    {
        my $Begin = substr($Str, 0, $MAXLENGTH);
        my $End = substr($Str, $MAXLENGTH);
        return ($Begin, divideStr($End));
    }
    else {
        return ($Str);
    }
}

sub get_Report_Files()
{
    my $Report = "";
    foreach my $Format (sort {$FormatInfo{$b}{"Weight"}<=>$FormatInfo{$a}{"Weight"}}
    sort {lc($FormatInfo{$a}{"Summary"}) cmp lc($FormatInfo{$b}{"Summary"})} keys(%FileChanges))
    {
        if(not $FileChanges{$Format}{"Total"}) {
            next;
        }
        $Report .= "<a name='".$FormatInfo{$Format}{"Anchor"}."'></a>\n";
        $Report .= "<h2>".$FormatInfo{$Format}{"Title"}." (".$FileChanges{$Format}{"Total"}.")</h2><hr/>\n";
        $Report .= "<table class='summary'>\n";
        $Report .= "<tr>";
        $Report .= "<th>Name</th>";
        $Report .= "<th>Status</th>";
        if($Format ne "DIR") {
            $Report .= "<th>Delta</th><th>Visual<br/>Diff</th><th>Detailed<br/>Report</th>";
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
            my ($Join, $Color1, $Color2) = ();
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
            $Report .= "<tr>\n";
            $Report .= "<td class='left f_path$Color1\'>".join("<br/>", divideStr($File))."</td>\n";
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
                    $Report .= "<td class='value'$Join>".show_number($Info{"Rate"}*100)."%</td>\n";
                }
                else {
                    $Report .= "<td$Join></td>\n";
                }
                if(my $Link = $Info{"Diff"}) {
                    $Report .= "<td$Join><a href='".$Link."' style='color:Blue;'>diff</a></td>\n";
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
                if(my $Link = $Info{"Report"}) {
                    $Report .= "<td$Join><a href='".$Link."' style='color:Blue;'>report</a></td>\n";
                }
                else {
                    $Report .= "<td$Join></td>\n";
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

sub appendFile($$)
{
    my ($Path, $Content) = @_;
    return if(not $Path);
    if(my $Dir = get_dirname($Path)) {
        mkpath($Dir);
    }
    open(FILE, ">>", $Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

sub writeFile($$)
{
    my ($Path, $Content) = @_;
    return if(not $Path);
    if(my $Dir = get_dirname($Path)) {
        mkpath($Dir);
    }
    open(FILE, ">", $Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

sub readFile($)
{
    my $Path = $_[0];
    return "" if(not $Path or not -f $Path);
    open(FILE, "<", $Path);
    local $/ = undef;
    my $Content = <FILE>;
    close(FILE);
    return $Content;
}

sub get_fileprefix($)
{
    if($_[0]=~/([^\/\\]+[\/\\]+[^\/\\]+)\Z/) {
        return $1;
    }
    return "";
}

sub get_filename($)
{ # much faster than basename() from File::Basename module
    if($_[0]=~/([^\/\\]+)[\/\\]*\Z/) {
        return $1;
    }
    return "";
}

sub get_dirname($)
{ # much faster than dirname() from File::Basename module
    if($_[0]=~/\A(.*?)[\/\\]+[^\/\\]*[\/\\]*\Z/) {
        return $1;
    }
    return "";
}

sub separate_path($) {
    return (get_dirname($_[0]), get_filename($_[0]));
}

sub checkCmd($)
{
    my $Cmd = $_[0];
    return "" if(not $Cmd);
    if(defined $Cache{"checkCmd"}{$Cmd}) {
        return $Cache{"checkCmd"}{$Cmd};
    }
    my @Options = (
        "--version",
        "-help"
    );
    foreach my $Opt (@Options)
    {
        my $Info = `$Cmd $Opt 2>$TMP_DIR/null`;
        if($Info) {
            return ($Cache{"checkCmd"}{$Cmd} = 1);
        }
    }
    return ($Cache{"checkCmd"}{$Cmd} = 0);
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

sub cut_path_prefix($$)
{
    my ($Path, $Prefix) = @_;
    return $Path if(not $Prefix);
    $Prefix=~s/[\/]+\Z//;
    $Path=~s/\A\Q$Prefix\E([\/]+|\Z)//;
    return $Path;
}

sub get_abs_path($)
{ # abs_path() should NOT be called for absolute inputs
  # because it can change them (symlinks)
    my $Path = $_[0];
    if($Path!~/\A\//) {
        $Path = abs_path($Path);
    }
    return $Path;
}

sub cmd_find($$$$)
{ # native "find" is much faster than File::Find (~6x)
  # also the File::Find doesn't support --maxdepth N option
  # so using the cross-platform wrapper for the native one
    my ($Path, $Type, $Name, $MaxDepth) = @_;
    return () if(not $Path or not -e $Path);
    $Path = get_abs_path($Path);
    if(-d $Path and -l $Path
    and $Path!~/\/\Z/)
    { # for directories that are symlinks
        $Path.="/";
    }
    my $Cmd = "find \"$Path\"";
    if($MaxDepth) {
        $Cmd .= " -maxdepth $MaxDepth";
    }
    if($Type) {
        $Cmd .= " -type $Type";
    }
    if($Name)
    { # file name
        if($Name=~/\]/) {
            $Cmd .= " -regex \"$Name\"";
        }
        else {
            $Cmd .= " -name \"$Name\"";
        }
    }
    return split(/\n/, `$Cmd 2>$TMP_DIR/null`);
}

sub generateTemplate()
{
    writeFile("VERSION.xml", $DescriptorTemplate."\n");
    printMsg("INFO", "XML-descriptor template ./VERSION.xml has been generated");
}

sub isSCM_File($)
{ # .svn, .git, .bzr, .hg and CVS
    my ($Dir, $Name) = separate_path($_[0]);
    if($Dir=~/(\A|[\/\\]+)\.(svn|git|bzr|hg)([\/\\]+|\Z)/) {
        return uc($2);
    }
    elsif($Name=~/\A\.(git|cvs|hg).*/)
    { # .gitignore, .gitattributes, .gitmodules, etc.
      # .cvsignore
        return uc($1);
    }
    elsif($Dir=~/(\A|[\/\\]+)(CVS)([\/\\]+|\Z)/) {
        return uc($2);
    }
    return "";
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
        if($Name=~/\.(\w+\.\w+)(\.in|)\Z/i
        and my $ID = $FileFormat{$Type}{$1})
        { # Double extension
            return $ID;
        }
        elsif($Name=~/\.(\w+)(\.in|)\Z/i
        and my $ID = $FileFormat{$Type}{$1})
        { # Single extension
            return $ID;
        }
    }
    return "";
}

sub getFormat($)
{
    my $Path = $_[0];
    return "" if(not $Path);
    if(defined $Cache{"getFormat"}{$Path}) {
        return $Cache{"getFormat"}{$Path};
    }
    my $Format = getFormat_($Path);
    
    if($Format eq "SHARED_OBJECT")
    { # Shared library
        if(getType($Path)=~/ASCII/i)
        {
            if(readFilePart($Path, 1)=~/GNU ld script/i) {
                $Format = "GNU_LD_SCRIPT";
            }
            else {
                $Format = "TEXT";
            }
        }
        return "SHARED_OBJECT";
    }
    
    if(not defined $FormatInfo{$Format}
    or not $FormatInfo{$Format}{"Summary"})
    { # Unknown
        $Format = "OTHER";
    }
    return ($Cache{"getFormat"}{$Path}=$Format);
}

sub getFormat_($)
{
    my $Path = $_[0];
    my ($Dir, $Name) = separate_path($Path);
    $Name=~s/\~\Z//g; # backup files
    if(-l $Path) {
        return "SYMLINK";
    }
    elsif(-d $Path) {
        return "DIR";
    }
    elsif(my $ID = identifyFile(get_filename($Path), "Name"))
    { # check by exact name (case sensitive)
        return $ID;
    }
    elsif(my $ID = identifyFile(get_filename($Path), "iName"))
    { # check by exact name
        return $ID;
    }
    elsif(my $Kind = isSCM_File($Path)) {
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
    elsif($Name=~/\A(INSTALL)(\.|\Z)/
    or $Name=~/\A[A-Z\-\_]+(\.txt|\.TXT|\Z)/
    or $Name=~/\A[A-Z\_]+\.[A-Z\_]+\Z/)
    { # HOWTO.DEBUG, BUGS, WISHLIST.TXT
        return "INFORM";
    }
    elsif((($Name=~/\.(gz|xz|lzma)\Z/i or $Name=~/\.(\d+)\Z/i)
    and $Dir=~/\/(man\d*|manpages)(\/|\Z)/)
    or ($Name=~/\.(\d+)\Z/i and $Dir=~/\/(doc|docs|src|libs|utils)(\/|\Z)/)
    or $Name=~/\.(man)\Z/ or $Name=~/[a-z]{3,}\.(\d+)\Z/i)
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
    elsif(my $ID = identifyFile(get_filename($Path), "Ext"))
    { # check by extension (case sensitive)
        return $ID;
    }
    elsif(my $ID = identifyFile(get_filename($Path), "iExt"))
    { # check by extension
        return $ID;
    }
    elsif(-f $Path)
    {
        my $Info = getType($Path);
        my @Terms = getTerms($Info);
        foreach my $Term (@Terms)
        {
            if($Term eq "TEXT"
            or $Term eq "DATA") {
                next;
            }
            if(defined $FormatInfo{$Term}
            and my $ID = $FormatInfo{$Term}{"ID"}) {
                return $ID;
            }
            elsif(my $ID = $TermFormat{$Term}) {
                return $ID;
            }
        }
        if($Info=~/compressed/i) {
            return "ARCHIVE";
        }
        elsif($Info=~/data/i) {
            return "DATA";
        }
        elsif($Info=~/text/i) {
            return "TEXT";
        }
        elsif($Info=~/executable/i) {
            return "EXE";
        }
        elsif($Info=~/\AELF\s/) {
            return "ELF_BINARY";
        }
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
    return if(not -f $Path);
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
        $Group{"V$Version"} = $GV;
    }
    else {
        exitStatus("Error", "version in the XML-descriptor is not specified (<version> section)");
    }
    if(my $GN = parseTag(\$Content, "group")) {
        $Group{"Name$Version"} = $GN;
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
                my @Files = cmd_find($Path, "f", "*.rpm", "");
                @Files = (@Files, cmd_find($Path, "f", "*.src.rpm", ""));
                if(not @Files)
                { # search for DEBs
                    @Files = (@Files, cmd_find($Path, "f", "*.deb", ""));
                }
                foreach (@Files) {
                    registerPackage($_, $Version);
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
    else {
        return ($Path, "Name");
    }
}

sub skip_file($$)
{
    my ($Path, $Version) = @_;
    return 0 if(not $Path or not $Version);
    my $Name = get_filename($Path);
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
        if($Name=~/$Pattern/) {
            return 1;
        }
        if($Pattern=~/[\/\\]/ and $Path=~/$Pattern/) {
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
    else {
        return ($Dep, "", "");
    }
}

sub registerPackage($$)
{
    my ($Path, $Version) = @_;
    return () if(not $Path or not -f $Path);
    my $PkgName = get_filename($Path);
    my $PkgFormat = getFormat($Path);
    my ($CPath, $Attr) = readPackage($Path, $Version);
    $TargetPackages{$Version}{$PkgName} = 1;
    $Group{"Count$Version"} += 1;
    my @Contents = listDir($CPath);
    my $Prefix = "";
    if($#Contents==0 and -d $CPath."/".$Contents[0]) {
        $Prefix = $Contents[0];
    }
    foreach my $File (cmd_find($CPath, "", "", ""))
    { # search for all files
        my $FName = cut_path_prefix($File, $CPath);
        if($PkgFormat eq "RPM"
        or $PkgFormat eq "DEB")
        { # files installed to the system
            $FName = "/".$FName;
        }
        elsif($PkgFormat eq "ARCHIVE")
        {
            if($Prefix) {
                $FName = cut_path_prefix($FName, $Prefix);
            }
        }
        if(not $FName) {
            next;
        }
        my $SubDir = "$TMP_DIR/xcontent$Version/$FName";
        $PackageFiles{$Version}{$FName} = $File;
        if(not get_dirname($FName)
        and getFormat($File) eq "ARCHIVE")
        { # go into archives (for SRPM)
            unpackArchive($File, $SubDir);
            my @SubContents = listDir($SubDir);
            my $G = "";
            if($#SubContents==0 and -d $SubDir."/".$SubContents[0])
            { # libsample-x.y.z.tar.gz/libsample-x.y.z
                $G = get_filename($File)."/".$SubContents[0];
                $SubDir .= "/".$SubContents[0];
            }
            foreach my $SubFile (cmd_find($SubDir, "", "", ""))
            { # search for all files in archive
                my $SFName = cut_path_prefix($SubFile, $SubDir);
                if(not $SFName) {
                    next;
                }
                $PackageFiles{$Version}{$SFName} = $SubFile;
                $FileGroup{$Version}{$SFName} = $G;
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
    return () if(not $Path or not -d $Path);
    opendir(my $DH, $Path);
    return () if(not $DH);
    my @Contents = grep { $_ ne "." && $_ ne ".." } readdir($DH);
    return @Contents;
}

sub getArchiveFormat($)
{
    my $Pkg = get_filename($_[0]);
    foreach (sort {length($b)<=>length($a)} keys(%ArchiveFormats))
    {
        my $P = $ArchiveFormats{$_};
        if($Pkg=~/\.($P)\Z/) {
            return $_;
        }
    }
    return "";
}

sub unpackArchive($$)
{
    my ($Pkg, $OutDir) = @_;
    mkpath($OutDir);
    my $Cmd = "";
    my $Format = getArchiveFormat($Pkg);
    if($Format eq "TAR.GZ") {
        $Cmd = "tar -xzf $Pkg --directory=$OutDir";
    }
    elsif($Format eq "TAR.BZ2") {
        $Cmd = "tar -xjf $Pkg --directory=$OutDir";
    }
    elsif($Format eq "TAR.XZ") {
        $Cmd = "tar -Jxf $Pkg --directory=$OutDir";
    }
    elsif($Format eq "TAR.LZMA") {
        $Cmd = "tar -xf $Pkg --lzma --directory=$OutDir";
    }
    elsif($Format eq "TAR.LZ") {
        $Cmd = "tar -xf $Pkg --lzip --directory=$OutDir";
    }
    elsif($Format eq "TAR") {
        $Cmd = "tar -xf $Pkg --directory=$OutDir";
    }
    elsif($Format eq "GZ") {
        $Cmd = "cp $Pkg $OutDir && cd $OutDir && gunzip ".get_filename($Pkg);
    }
    elsif($Format eq "LZMA") {
        $Cmd = "cp $Pkg $OutDir && cd $OutDir && unlzma ".get_filename($Pkg);
    }
    elsif($Format eq "XZ") {
        $Cmd = "cp $Pkg $OutDir && cd $OutDir && unxz ".get_filename($Pkg);
    }
    elsif($Format eq "ZIP") {
        $Cmd = "unzip $Pkg -d $OutDir";
    }
    elsif($Format eq "JAR") {
        $Cmd = "cd $OutDir && jar -xf $Pkg";
    }
    else {
        return "";
    }
    system($Cmd." >$TMP_DIR/null 2>&1");
}

sub readPackage($$)
{
    my ($Path, $Version) = @_;
    return "" if(not $Path or not -f $Path);
    my $CPath = "$TMP_DIR/content$Version/".get_filename($Path);
    my %Attributes = ();
    my $Format = getFormat($Path);
    if($Format eq "DEB")
    { # Deb package
        if(not checkCmd("dpkg-deb")) {
            exitStatus("Not_Found", "can't find \"dpkg-deb\"");
        }
        mkpath($CPath);
        system("dpkg-deb --extract $Path $CPath");
        if($?) {
            exitStatus("Error", "can't extract package v$Version");
        }
        if(not checkCmd("dpkg")) {
            exitStatus("Not_Found", "can't find \"dpkg\"");
        }
        my $Info = `dpkg -f $Path`;
        if($Info=~/Version\s*:\s*(.+)/) {
            $Attributes{"Version"} = $1;
        }
        if($Info=~/Package\s*:\s*(.+)/) {
            $Attributes{"Name"} = $1;
        }
        if($Info=~/Architecture\s*:\s*(.+)/) {
            $Attributes{"Arch"} = $1;
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
        $PackageInfo{$Attributes{"Name"}}{"V$Version"} = $Info;
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
        system("cd $CPath && rpm2cpio \"".abs_path($Path)."\" | cpio -id --quiet");
        if($?) {
            exitStatus("Error", "can't extract package v$Version");
        }
        ($Attributes{"Version"}, $Attributes{"Release"},
        $Attributes{"Name"}, $Attributes{"Arch"}) = split(",", readRPM($Path, "--queryformat \%{version},\%{release},\%{name},\%{arch}"));
        if($Attributes{"Release"}) {
            $Attributes{"Version"} .= "-".$Attributes{"Release"};
        }
        foreach my $Kind ("requires", "provides", "suggests")
        {
            foreach my $D (split("\n", readRPM($Path, "--".$Kind)))
            {
                my ($N, $Op, $V) = sepDep($D);
                %{$PackageDeps{$Version}{$Kind}{$N}} = ( "Op"=>$Op, "V"=>$V );
                $TotalDeps{$Kind." ".$N} = 1;
            }
        }
        $PackageInfo{$Attributes{"Name"}}{"V$Version"} = readRPM($Path, "--info");
        $Group{"Format"}{$Format} = 1;
    }
    elsif($Format eq "ARCHIVE")
    { # TAR.GZ and others
        unpackArchive(abs_path($Path), $CPath);
        if(my ($N, $V) = getPkgVersion(get_filename($Path))) {
            ($Attributes{"Name"}, $Attributes{"Version"}) = ($N, $V);
        }
        if(not $Attributes{"Version"})
        { # default version
            $Attributes{"Version"} = $Version;
        }
        if(not $Attributes{"Name"})
        { # default name
            $Attributes{"Name"} = get_filename($Path);
            $Attributes{"Name"}=~s/\.($ARCHIVE_EXT)\Z//;
        }
        $Group{"Format"}{uc(getExt($Path))} = 1;
    }
    return ($CPath, \%Attributes);
}

sub getPkgVersion($)
{
    my $Name = $_[0];
    my $Extension = getExt($Name);
    $Name=~s/\.(\Q$Extension\E)\Z//;
    if($Name=~/\A(.+[a-z])[\-\_](\d.+?)\Z/i)
    { # libsample-N
        return ($1, $2);
    }
    elsif($Name=~/\A(.+)[\-\_](.+?)\Z/i)
    { # libsample-N
        return ($1, $2);
    }
    elsif($Name=~/\A(.+?)(\d[\d\.]*)\Z/i)
    { # libsampleN
        return ($1, $2);
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

sub readRPM($$)
{
    my ($Path, $Query) = @_;
    return `rpm -qp $Query $Path 2>$TMP_DIR/null`;
}

sub get_Footer($)
{
    my $Name = $_[0];
    my $Footer = "<div style='width:100%;font-size:11px;' align='right'><i>Generated on ".(localtime time); # report date
    $Footer .= " by <a href='".$HomePage{"Dev"}."'>Package Changes Analyzer</a> - PkgDiff"; # tool name
    my $ToolSummary = "<br/>A tool for analyzing changes in Linux software packages&#160;&#160;";
    $Footer .= " $TOOL_VERSION &#160;$ToolSummary</i></div>"; # tool version
    return $Footer;
}

sub composeHTML_Head($$$$)
{
    my ($Title, $Keywords, $Description, $OtherInHead) = @_;
    return "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">\n<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\">\n<head>
    <meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />
    <meta name=\"keywords\" content=\"$Keywords\" />
    <meta name=\"description\" content=\"$Description\" />
    <title>\n        $Title\n    </title>\n$OtherInHead\n</head>";
}

sub get_Header()
{
    my $Header = "";
    if($CheckMode eq "Group") { 
        $Header = "<h1>Changes report for the <span style='color:Blue;'>".$Group{"Name"}."</span> group of packages between <span style='color:Red;'>".$Group{"V1"}."</span> and <span style='color:Red;'>".$Group{"V2"}."</span> versions</h1>";
    }
    else
    { # single package
        $Header = "<h1>Changes report for the <span style='color:Blue;'>".$Group{"Name"}."</span> package between <span style='color:Red;'>".$Group{"V1"}."</span> and <span style='color:Red;'>".$Group{"V2"}."</span> versions</h1>";
    }
    return $Header;
}

sub show_number($)
{
    if($_[0])
    {
        my $Num = cut_off_number($_[0], 2, 0);
        if($Num eq "0")
        {
            foreach my $P (3 .. 7)
            {
                $Num = cut_off_number($_[0], $P, 1);
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

sub cut_off_number($$$)
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

sub get_Summary()
{
    my $TestInfo = "<h2>Test Info</h2><hr/>\n";
    $TestInfo .= "<table class='summary'>\n";
    if($CheckMode eq "Group") {
        $TestInfo .= "<tr><th class='left'>Group Name</th><td>".$Group{"Name"}."</td></tr>\n";
    }
    else {
        $TestInfo .= "<tr><th class='left'>Package Name</th><td>".$Group{"Name"}."</td></tr>\n";
    }
    my @Formats = sort keys(%{$Group{"Format"}});
    $TestInfo .= "<tr><th class='left'>Package Format</th><td>".join(", ", @Formats)."</td></tr>\n";
    if($Group{"Arch"}) {
        $TestInfo .= "<tr><th class='left'>Package Arch</th><td>".$Group{"Arch"}."</td></tr>\n";
    }
    $TestInfo .= "<tr><th class='left'>Version #1</th><td>".$Group{"V1"}."</td></tr>\n";
    $TestInfo .= "<tr><th class='left'>Version #2</th><td>".$Group{"V2"}."</td></tr>\n";
    if($QuickMode) {
        $TestInfo .= "<tr><th class='left'>Mode</th><td>Quick</td></tr>\n";
    }
    $TestInfo .= "</table>\n";

    my $TestResults = "<h2>Test Results</h2><hr/>\n";
    $TestResults .= "<table class='summary'>\n";
    
    my $Packages_Link = "0";
    my %TotalPackages = map {$_=>1} (keys(%{$TargetPackages{1}}), keys(%{$TargetPackages{2}}));
    if(keys(%TotalPackages)>0) {
        $Packages_Link = "<a href='#Packages' style='color:Blue;'>".keys(%TotalPackages)."</a>";
    }
    $TestResults .= "<tr><th class='left'>Total Packages</th><td>".$Packages_Link."</td></tr>\n";
    
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
    foreach my $Format (keys(%FileChanges))
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
    $Affected = show_number($Affected);
    if($Affected>=100) {
        $Affected = 100;
    }
    
    my $Verdict = "";
    if($TotalChanged)
    {
        $Verdict = "<span style='color:Red;'><b>Changed<br/>(".$Affected."%)</b></span>";
        $RESULT{"compat"} = "Incompatible";
    }
    else
    {
        $Verdict = "<span style='color:Green;'><b>Unchanged</b></span>";
        $RESULT{"compat"} = "Compatible";
    }
    $TestResults .= "<tr><th class='left'>Verdict</th><td>$Verdict</td></tr>\n";
    $TestResults .= "</table>\n";
    
    my $FileChanges = "<a name='Files'></a><h2>Changes In Files</h2><hr/>\n";
    $FileChanges .= "<table class='summary'>\n";
    $FileChanges .= "<tr><th>File Type</th><th>Total</th><th>Added</th><th>Removed</th><th>Changed</th></tr>\n";
    foreach my $Format (sort {$FormatInfo{$b}{"Weight"}<=>$FormatInfo{$a}{"Weight"}}
    sort {lc($FormatInfo{$a}{"Summary"}) cmp lc($FormatInfo{$b}{"Summary"})} keys(%FormatInfo))
    {
        if(not $FileChanges{$Format}{"Total"}) {
            next;
        }
        $FileChanges .= "<tr>\n";
        $FileChanges .= "<td class='left'>".$FormatInfo{$Format}{"Summary"}."</td>\n";
        foreach ("Total", "Added", "Removed", "Changed")
        {
            if($FileChanges{$Format}{$_}>0)
            {
                my $Link = "<a href='#".$FormatInfo{$Format}{"Anchor"}."' style='color:Blue;'>".$FileChanges{$Format}{$_}."</a>";
                if($_ eq "Added") {
                    $FileChanges .= "<td class='new'>".$Link."</td>\n";
                }
                elsif($_ eq "Removed") {
                    $FileChanges .= "<td class='failed'>".$Link."</td>\n";
                }
                elsif($_ eq "Changed") {
                    $FileChanges .= "<td class='warning'>".$Link."</td>\n";
                }
                else {
                    $FileChanges .= "<td>".$Link."</td>\n";
                }
            }
            else {
                $FileChanges .= "<td>0</td>\n";
            }
        }
        $FileChanges .= "</tr>\n";
    }
    $FileChanges .= "</table>\n";
    my $Legend = "<br/><table class='summary'>
    <tr><td class='new' width='80px'>added</td><td class='passed' width='80px'>unchanged</td></tr>
    <tr><td class='warning'>changed</td><td class='failed'>removed</td></tr></table>\n";
    return $Legend.$TestInfo.$TestResults.get_Report_Headers().get_Report_Deps().$FileChanges;
}

sub get_Source()
{
    my $Packages = "<a name='Packages'></a>\n";
    my %Pkgs = map {$_=>1} (keys(%{$TargetPackages{1}}), keys(%{$TargetPackages{2}}));
    $Packages .= "<h2>Packages (".keys(%Pkgs).")</h2><hr/>\n";
    $Packages .= "<div class='p_list'>\n";
    foreach my $Name (sort keys(%Pkgs)) {
        $Packages .= $Name."<br/>\n";
    }
    $Packages .= "</div>\n";
    $Packages .= "<br/><a style='font-size:11px;' href='#Top'>to the top</a><br/>\n";
    return $Packages;
}

sub createReport($)
{
    my $Path = $_[0];
    my $CssStyles = readStyles("Index.css");
    printMsg("INFO", "creating changes report ...");
    
    my $Title = $Group{"Name"}.": ".$Group{"V1"}." to ".$Group{"V2"}." changes report";
    my $Keywords = $Group{"Name"}.", changes, report";
    my $Header = get_Header();
    my $Description = $Header;
    $Description=~s/<[^<>]+>//g;
    my $Report = composeHTML_Head($Title, $Keywords, $Description, $CssStyles)."\n<body>\n<div><a name='Top'></a>\n";
    $Report .= $Header."\n";
    my $MainReport = get_Report_Files();
    $Report .= get_Summary();
    $Report .= $MainReport;
    $Report .= get_Report_Usage();
    $Report .= get_Source();
    $Report .= "</div>\n<br/><br/><br/><hr/>\n";
    $Report .= get_Footer($Group{"Name"});
    $Report .= "\n<div style='height:999px;'></div>\n</body></html>";
    writeFile($Path, $Report);
    printMsg("INFO", "see detailed report:\n  $Path");
    if($Browse) {
        system($Browse." \"".$Path."\" >/dev/null 2>&1 &");
    }
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
        if(my $Weight = parseTag(\$FileType, "weight")) {
            $FormatInfo{$ID}{"Weight"} = $Weight;
        }
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
    if(not $Title=~s/y\Z/ies/)
    { # scripts, files, libraries
        if(not $Title=~s/ch\Z/ches/)
        { # patches
            $Title .= "s";
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

sub get_dumpversion($)
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

sub scenario()
{
    if($Help) {
        HELP_MESSAGE();
        exit(0);
    }
    if($ShowVersion) {
        printMsg("INFO", "Package Changes Analyzer (pkgdiff) $TOOL_VERSION\nCopyright (C) 2012 ROSA Laboratory\nLicense: GNU GPL <http://www.gnu.org/licenses/>\nThis program is free software: you can redistribute it and/or modify it.\n\nWritten by Andrey Ponomarenko.");
        exit(0);
    }
    if($DumpVersion) {
        printMsg("INFO", $TOOL_VERSION);
        exit(0);
    }
    if($GenerateTemplate) {
        generateTemplate();
        exit(0);
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
    if(my $V = get_dumpversion($ABICC))
    {
        if(cmpVersions($V, "1.96")==-1)
        {
            printMsg("WARNING", "unsupported version of ABI Compliance Checker detected");
            $ABICC = "";
        }
    }
    if(not $Descriptor{1}) {
        exitStatus("Error", "-old option is not specified");
    }
    if(not -f $Descriptor{1}) {
        exitStatus("Access_Error", "can't access file \'".$Descriptor{1}."\'");
    }
    if(not $Descriptor{2}) {
        exitStatus("Error", "-new option is not specified");
    }
    if(not -f $Descriptor{2}) {
        exitStatus("Access_Error", "can't access file \'".$Descriptor{2}."\'");
    }
    readFileTypes();
    printMsg("INFO", "reading packages ...");
    if(getFormat($Descriptor{1})=~/\A(RPM|SRPM|DEB|ARCHIVE)\Z/)
    {
        my $Attr = registerPackage($Descriptor{1}, 1);
        $Group{"Name1"} = $Attr->{"Name"};
        $Group{"V1"} = $Attr->{"Version"};
        $Group{"Arch1"} = $Attr->{"Arch"};
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
    if(getFormat($Descriptor{2})=~/\A(RPM|SRPM|DEB|ARCHIVE)\Z/)
    {
        my $Attr = registerPackage($Descriptor{2}, 2);
        $Group{"Name2"} = $Attr->{"Name"};
        $Group{"V2"} = $Attr->{"Version"};
        $Group{"Arch2"} = $Attr->{"Arch"};
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
    if($Group{"Count1"} ne $Group{"Count2"}) {
        printMsg("WARNING", "different number of packages in descriptors");
    }
    $Group{"Arch"} = $Group{"Arch1"};
    if($Group{"Arch1"} ne $Group{"Arch2"}) {
        printMsg("WARNING", "different architectures of packages (\"".$Group{"Arch1"}."\" and \"".$Group{"Arch2"}."\")");
    }
    if(defined $Group{"Format"}{"DEB"}
    and defined $Group{"Format"}{"RPM"}) {
        printMsg("WARNING", "incompatible package formats: RPM and DEB");
    }
    if($OutputReportPath)
    { # user-defined path
        $REPORT_PATH = $OutputReportPath;
        $REPORT_DIR = get_dirname($REPORT_PATH);
        if(not $REPORT_DIR) {
            $REPORT_DIR = ".";
        }
    }
    else
    {
        $REPORT_DIR = "pkgdiff_reports/".$Group{"Name"}."/".$Group{"V1"}."_to_".$Group{"V2"};
        $REPORT_PATH = $REPORT_DIR."/compat_report.html";
        if(-d $REPORT_DIR)
        {
            rmtree($REPORT_DIR."/info-diffs");
            rmtree($REPORT_DIR."/diffs");
            rmtree($REPORT_DIR."/details");
        }
    }
    printMsg("INFO", "comparing packages ...");
    detectChanges();
    createReport($REPORT_PATH);
    exit($ERROR_CODE{$RESULT{"compat"}});
}

scenario();
