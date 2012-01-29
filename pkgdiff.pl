#!/usr/bin/perl
###########################################################################
# pkgdiff - Package Changes Analyzer 1.0
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
#  GNU Wdiff
#  GNU Awk
#  RPM (rpm, rpmbuild, rpm2cpio) for analysis of RPM-packages
#  DPKG (dpkg, dpkg-deb) for analysis of DEB-packages
#
# SUGGESTIONS
# ===========
#  ABI Compliance Checker (>=1.96)
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
use Cwd qw(abs_path cwd);

my $TOOL_VERSION = "1.0";
my $ORIG_DIR = cwd();
my $TMP_DIR = tempdir(CLEANUP=>1);

# Internal modules
my $MODULES_DIR = get_Modules();
push(@INC, get_dirname($MODULES_DIR));

my $DIFF = $MODULES_DIR."/Internals/Tools/rfcdiff";
my $ABICC = "abi-compliance-checker";

my ($Help, $ShowVersion, $DumpVersion, $GenerateTemplate, %Descriptor,
$CheckUsage, $PackageManager, $OutputReportPath, $ShowDetails, $Debug);

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
  "t|template!" => \$GenerateTemplate,
  "report-path=s" => \$OutputReportPath,
  "details" => \$ShowDetails,
  "debug" => \$Debug
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
  -old <path>
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

  -new <path>
      Path to the new version of a package (RPM, DEB, TAR.GZ, etc).

OTHER OPTIONS:
  -check-usage
      Check if package content is used by other
      packages in the repository.

  -pkg-manager <name>
      Specify package management tool.
      Supported:
        urpm - Mandriva URPM

  -t|-template
      Create XML-descriptor template ./VERSION.xml

  -report-path <path>
      Path to the report.
      Default:
        pkgdiff_reports/<pkg>/<v1>_to_<v2>/compat_report.html

  -details
      Try to create detailed reports.

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

</descriptor>";

my %Group = (
    "Count1"=>0,
    "Count2"=>0
);

my %FormatInfo = (
    "HEADER" => {
        "Descr"=>"Header file",
        "N"=>10
    },
    "C_SRC" => {
        "Descr"=>"C program",
        "N"=>9
    },
    "CPP_SRC" => {
        "Descr"=>"CPP program",
        "N"=>8
    },
    "F_SRC" => {
        "Descr"=>"Fortran program",
        "N"=>7
    },
    "SHLIB" => {
        "Descr"=>"Shared library",
        "N"=>9
    },
    "EXE" => {
        "Descr"=>"Executable file",
        "N"=>5
    },
    "STLIB" => {
        "Descr"=>"Static library",
        "N"=>8
    },
    "PKGCONFIG" => {
        "Descr"=>"Pkg-config metadata",
        "Title"=>"Pkg-config Metadata Files",
        "Anchor"=>"PkgConfigs",
        "N"=>5
    },
    "DOXYGEN" => {
        "Descr"=>"Doxygen file",
        "N"=>5
    },
    "AUTOMAKE" => {
        "Descr"=>"Automake files",
        "N"=>5
    },
    "MAKEFILE" => {
        "Descr"=>"Makefile",
        "N"=>5
    },
    "CMAKE" => {
        "Descr"=>"Cmake file",
        "N"=>5
    },
    "XML" => {
        "Descr"=>"XML file",
        "N"=>5
    },
    "SGML" => {
        "Descr"=>"SGML document",
        "N"=>5
    },
    "XBEL" => {
        "Descr"=>"XBEL bookmark",
        "N"=>5
    },
    "MANPAGE" => {
        "Descr"=>"Man page",
        "N"=>5
    },
    "DIR" => {
        "Descr"=>"Directory",
        "N"=>1
    },
    "SYMLINK" => {
        "Descr"=>"Symbolic link",
        "N"=>3
    },
    "TEXT" => {
        "Descr"=>"Text file",
        "N"=>1
    },
    "LIBTOOL" => {
        "Descr"=>"Libtool library file",
        "Anchor"=>"LibtoolFiles",
        "N"=>5
    },
    "PS" => {
        "Descr"=>"PostScript file",
        "N"=>5
    },
    "DESKTOP" => {
        "Descr"=>"Desktop entry",
        "N"=>5
    },
    "HTML" => {
        "Descr"=>"HTML page",
        "Anchor"=>"HTML",
        "N"=>3
    },
    "CSS" => {
        "Descr"=>"CSS style sheet",
        "Title"=>"CSS Style Sheets",
        "Anchor"=>"CSS",
        "N"=>3
    },
    "M4" => {
        "Descr"=>"M4 macro file",
        "Anchor"=>"M4",
        "N"=>3
    },
    "SHELL" => {
        "Descr"=>"Shell program",
        "N"=>4
    },
    "PERL" => {
        "Descr"=>"Perl program",
        "N"=>4
    },
    "PYTHON" => {
        "Descr"=>"Python program",
        "N"=>4
    },
    "RUBY" => {
        "Descr"=>"Ruby program",
        "N"=>4
    },
    "JAVA" => {
        "Descr"=>"Java program",
        "N"=>4
    },
    "GETTEXT" => {
        "Descr"=>"Gettext file",
        "N"=>4
    },
    "IMAGE" => {
        "Descr"=>"Image",
        "Descr"=>"Images",
        "N"=>2
    },
    "PARAM" => {
        "Descr"=>"Parameter file",
        "N"=>5
    },
    "SPEC" => {
        "Descr"=>"Spec file",
        "N"=>9
    },
    "PATCH" => {
        "Descr"=>"Patch",
        "Descr"=>"Patches",
        "N"=>8
    },
    "MSVC" => {
        "Descr"=>"MSVC file",
        "N"=>5
    },
    "OOO" => {
        "Descr"=>"OpenOffice file",
        "N"=>5
    },
    "LICENSE" => {
        "Descr"=>"License",
        "Title"=>"Licenses",
        "N"=>1
    },
    "ARCHIVE" => {
        "Descr"=>"Archive",
        "Title"=>"Archives",
        "N"=>1
    },
    "OTHER" => {
        "Descr"=>"Other",
        "Title"=>"Other Files",
        "N"=>0
    }
);

# Cache
my %Cache;

# Modes
my $CheckMode = "Single";

# Packages
my %TargetPackages;
my %PackageFiles;
my %FileChanges;
my %PackageInfo;
my %FileGroup;
my %PackageUsage;
my %TotalUsage;
my %FormatFiles;

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

# Report
my $REPORT_PATH;
my $REPORT_DIR;
my %RESULT;

# Other
my $ARCHIVE_EXT = "tar\.gz|tgz|tar\.z|tar\.xz|tar\.bz2|txz|zip|tar|lzma|gz|jar";

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
    if(cmpBytes($P1, $P2)==0)
    { # compare md5 sum or size
        return (-1, "", "");
    }
    my ($Changed, $DLink, $RLink) = ();
    if($Format eq "HEADER"
    or $Format eq "PKGCONFIG"
    or $Format eq "TEXT"
    or $Format eq "LIBTOOL"
    or $Format eq "DESKTOP"
    or $Format eq "PARAM"
    or $Format eq "M4"
    or $Format eq "SHELL"
    or $Format eq "PERL"
    or $Format eq "PYTHON"
    or $Format eq "RUBY"
    or $Format eq "JAVA"
    or $Format eq "LICENSE"
    or $Format eq "DOXYGEN"
    or $Format eq "AUTOMAKE"
    or $Format eq "MAKEFILE"
    or $Format eq "CMAKE"
    or $Format eq "XML"
    or $Format eq "XBEL"
    or $Format eq "SGML"
    or $Format eq "SPEC"
    or $Format eq "PATCH"
    or $Format eq "C_SRC"
    or $Format eq "CPP_SRC"
    or $Format eq "F_SRC")
    {
        $DLink = diffFiles($P1, $P2, getRPath("diffs", $N1));
    }
    elsif($Format eq "SHLIB"
    or $Format eq "MANPAGE"
    or $Format eq "SYMLINK")
    {
        my $Page1 = showFile($P1, $Format, 1);
        my $Page2 = showFile($P2, $Format, 2);
        if($Format eq "SYMLINK")
        {
            if(readFile($Page1) eq readFile($Page2)) {
                return ();
            }
        }
        $DLink = diffFiles($Page1, $Page2, getRPath("diffs", $N1));
    }
    else {
        $Changed = 1;
    }
    if($DLink or $Changed)
    {
        if($ShowDetails)
        { # --details
            if($ABICC)
            {
                if($Format eq "SHLIB"
                or $Format eq "STLIB"
                or $Format eq "HEADER") {
                    $RLink = runABICC(getRPath("details", "abi"));
                }
            }
        }
        $DLink =~s/\A\Q$REPORT_DIR\E\///;
        $RLink =~s/\A\Q$REPORT_DIR\E\///;
        return (1, $DLink, $RLink);
    }
    else {
        return ();
    }
}

sub showFile($$$)
{
    my ($Path, $Format, $Version) = @_;
    my $Name = get_filename($Path);
    my $Cmd = "";
    if($Format eq "MANPAGE")
    {
        $Name=~s/\.(gz|bz2|xz)\Z//;
        $Cmd = "man";
    }
    elsif($Format eq "SHLIB"
    or $Format eq "STLIB")
    {
        $Cmd = "readelf -Wa";
    }
    elsif($Format eq "SYMLINK")
    {
        $Cmd = "file -b";
    }
    my $SPath = $TMP_DIR."/".$Format."/".$Version."/".$Name;
    mkpath(get_dirname($SPath));
    system($Cmd." $Path >$SPath 2>$TMP_DIR/null");
    if($Format eq "SHLIB")
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

sub cmpBytes($$)
{
    my ($P1, $P2) = @_;
    if(not -f $P1
    or not -f $P2)
    {
        if(-l $P1)
        { # broken symlinks
            return 1;
        }
        else {
            return 0;
        }
    }
    if(-s $P1 != -s $P2) {
        return 1;
    }
    return (getMD5($P1) ne getMD5($P2));
}

sub getMD5($)
{
    my $Path = $_[0];
    if(not $Path) {
        return 0;
    }
    my $MD5 = `md5sum $Path`;
    if($MD5=~/\A(\w+)/) {
        return $1;
    }
    return 0;
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
    my @L1 = keys(%{$FormatFiles{"1"}{"SHLIB"}});
    my @L2 = keys(%{$FormatFiles{"2"}{"SHLIB"}});
    my @SL1 = keys(%{$FormatFiles{"1"}{"STLIB"}});
    my @SL2 = keys(%{$FormatFiles{"2"}{"STLIB"}});
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
    $Cmd .= " --report-path=$Path";
    $Cmd .= " --log-path=$REPORT_DIR/logs/abicc-log.txt";
    $Cmd .= " -quiet";
    system($Cmd);
    my $Ret = $?>>8;
    if($Ret==0 or $Ret==1)
    { # the tool has run without any errors
        return ($Cache{"runABICC"} = $Path);
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

sub diffFiles($$$)
{
    my ($P1, $P2, $Path) = @_;
    mkpath(get_dirname($Path));
    system("sh $DIFF --width 75 --stdout $P1 $P2 >$Path 2>$TMP_DIR/null");
    if(-s $Path<3500)
    { # may be identical
        if(readFilePart($Path, 2)=~/The files are identical/)
        {
            unlink($Path);
            return "";
        }
    }
    return $Path;
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
    return `file -b \"$Path\"`;
}

sub isRenamed($$)
{
    my ($P1, $P2) = @_;
    my ($D1, $N1) = separate_path($P1);
    my ($D2, $N2) = separate_path($P2);
    if($D1 ne $D2) {
        return 0;
    }
    if($N1 eq $N2) {
        return 0;
    }
    my $HL = (length($N1)+length($N2))/4;
    return (length(getBaseStr($N1, $N2))>=$HL);
}

sub getBaseStr($$)
{
    my ($Str1, $Str2) = @_;
    my $SubStr = "";
    foreach (0 .. length($Str1) - 1)
    {
        my $S1 = substr($Str1, $_, 1);
        my $S2 = substr($Str2, $_, 1);
        if($S1 eq $S2) {
            $SubStr.=$S1;
        }
        else {
            return $SubStr;
        }
    }
    return $SubStr;
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
#     while($D1 ne "/" and get_dirname($D1))
#     {
#         if(isRenamed($D1, $D2)) {
#             return 1;
#         }
#         elsif()
#         $D1 = get_dirname($D1);
#         $D2 = get_dirname($D2);
#     }
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
    foreach my $Name (sort keys(%{$PackageFiles{1}}))
    { # detect removed files
        my $Format = getFormat($PackageFiles{1}{$Name});
        $FormatFiles{1}{$Format}{$PackageFiles{1}{$Name}}=1;
        if(not defined $PackageFiles{2}{$Name}) {
            $RemovedFiles{$Name}=1;
        }
        else {
            $StableFiles{$Name}=1;
        }
    }
    my (%AddedByDir, %AddedByName) = ();
    foreach my $Name (keys(%{$PackageFiles{2}}))
    { # checking added files
        my $Format = getFormat($PackageFiles{2}{$Name});
        $FormatFiles{2}{$Format}{$PackageFiles{2}{$Name}}=1;
        if(not defined $PackageFiles{1}{$Name})
        {
            $AddedFiles{$Name}=1;
            $AddedByDir{get_dirname($Name)}{$Name}=1;
            $AddedByName{get_filename($Name)}{$Name}=1;
        }
    }
    foreach my $Name (sort keys(%RemovedFiles))
    { # checking removed files
        my $Format = getFormat($PackageFiles{1}{$Name});
        $FileChanges{$Format}{"Total"} += 1;
        $FileChanges{$Format}{"Removed"} += 1;
        $FileChanges{$Format}{"Details"}{$Name}{"Status"} = "removed";
    }
    foreach my $Name (sort keys(%RemovedFiles))
    { # checking renamed files
        my $Format = getFormat($PackageFiles{1}{$Name});
        foreach my $Added (sort keys(%{$AddedByDir{get_dirname($Name)}}))
        {
            if($Format ne getFormat($PackageFiles{2}{$Added}))
            { # different formats
                next;
            }
            if(isRenamed($Name, $Added))
            {
                $RenamedFiles{$Name} = $Added;
                $RenamedFiles_R{$Added} = $Name;
            }
        }
    }
    foreach my $Name (sort keys(%RemovedFiles))
    { # checking moved files
        my $Format = getFormat($PackageFiles{1}{$Name});
        foreach my $Added (sort keys(%{$AddedByName{get_filename($Name)}}))
        {
            if($Format ne getFormat($PackageFiles{2}{$Added}))
            { # different formats
                next;
            }
            if(isMoved($Name, $Added))
            {
                $MovedFiles{$Name} = $Added;
                $MovedFiles_R{$Added} = $Name;
            }
        }
    }
    foreach my $Name (sort (keys(%StableFiles), keys(%RenamedFiles), keys(%MovedFiles)))
    { # checking files
        my $Path = $PackageFiles{1}{$Name};
        if($Debug) {
            print "$Name\n";
        }
        my ($NewPath, $NewName) = ($PackageFiles{2}{$Name}, $Name);
        my $Format = getFormat($Path);
        if($StableFiles{$Name})
        { # stable files
            $FileChanges{$Format}{"Total"} += 1;
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
        my ($Changed, $DLink, $RLink) = compareFiles($Path, $NewPath, $Name, $NewName);
        if($Changed==1)
        {
            if($NewName eq $Name)
            { # renamed and moved files should
              # not be shown in the summary
                $FileChanges{$Format}{"Changed"} += 1;
            }
            $Details{"Status"} = "changed";
            $Details{"Diff"} = $DLink;
            $Details{"Report"} = $RLink;
        }
        elsif($Changed==-1)
        {
            $Details{"Status"} = "unchanged";
            $Details{"Diff"} = "empty";
        }
        else
        {
            $Details{"Status"} = "unchanged";
        }
        if($NewName = $RenamedFiles{$Name})
        { # renamed files
            $Details{"Status"} = "renamed";
        }
        elsif($NewName = $MovedFiles{$Name})
        { # moved files
            $Details{"Status"} = "moved";
        }
        %{$FileChanges{$Format}{"Details"}{$Name}} = %Details;
    }
    foreach my $Name (keys(%AddedFiles))
    { # checking added files
        my $Format = getFormat($PackageFiles{2}{$Name});
        $FileChanges{$Format}{"Total"} += 1;
        $FileChanges{$Format}{"Added"} += 1;
        $FileChanges{$Format}{"Details"}{$Name}{"Status"} = "added";
    }

    # Deps
    foreach my $Kind (keys(%{$PackageDeps{1}}))
    { # removed/changed deps
        foreach my $Name (keys(%{$PackageDeps{1}{$Kind}}))
        {
            if(not defined($PackageDeps{2}{$Kind})
            or not defined($PackageDeps{2}{$Kind}{$Name}))
            {
                $DepChanges{$Kind}{"Details"}{$Name}{"Status"} = "removed";
                next;
            }
            my %Info1 = %{$PackageDeps{1}{$Kind}{$Name}};
            my %Info2 = %{$PackageDeps{2}{$Kind}{$Name}};
            if($Info1{"Op"} and $Info1{"V"}
            and ($Info1{"Op"} ne $Info2{"Op"} or $Info1{"V"} ne $Info2{"V"})) {
                $DepChanges{$Kind}{"Details"}{$Name}{"Status"} = "changed";
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
                $DepChanges{$Kind}{"Details"}{$Name}{"Status"} = "added";
            }
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
    $Report .= "<table cellpadding='3' cellspacing='0' class='summary'>\n";
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
    $Report .= "<table cellpadding='3' cellspacing='0' class='summary'>\n";
    $Report .= "<tr><th>Package</th><th>Status</th><th>HTML Diff</th></tr>\n";
    foreach my $Package (sort keys(%PackageInfo))
    {
        my $Old = $PackageInfo{$Package}{"V1"};
        my $New = $PackageInfo{$Package}{"V2"};
        my $DLink = "";
        if($Old ne $New)
        {
            my $P1 = $TMP_DIR."/1/".$Package."-info";
            my $P2 = $TMP_DIR."/2/".$Package."-info";
            writeFile($P1, $Old);
            writeFile($P2, $New);
            $DLink = diffFiles($P1, $P2, getRPath("info-diffs", $Package."-info"));
            $DLink =~s/\A\Q$REPORT_DIR\E\///;
        }
        $Report .= "<tr>\n";
        $Report .= "<td class='left f_path'>$Package</td>\n";
        if($DLink)
        {
            $Report .= "<td class='warning'>changed</td>\n";
            $Report .= "<td><a href='".$DLink."' style='color:Blue;'>diff</a></td>\n";
        }
        else
        {
            $Report .= "<td class='passed'>unchanged</td>\n";
            $Report .= "<td></td>\n";
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
        $Report .= "<table cellpadding='3' cellspacing='0' class='summary'>\n";
        $Report .= "<tr><th>Name</th><th>Status</th><th>Version #1</th><th>Version #2</th></tr>\n";
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
            
            $Report .= "<td>".htmlSpecChars($PackageDeps{1}{$Kind}{$Name}{"Op"}." ".$PackageDeps{1}{$Kind}{$Name}{"V"})."</td>\n";
            $Report .= "<td>".htmlSpecChars($PackageDeps{2}{$Kind}{$Name}{"Op"}." ".$PackageDeps{2}{$Kind}{$Name}{"V"})."</td>\n";
            
            $Report .= "</tr>\n";
        }
        $Report .= "</table>\n";
    }
    return $Report;
}

sub get_Report_Files()
{
    my $Report = "";
    foreach my $Format (sort {$FormatInfo{$b}{"N"}<=>$FormatInfo{$a}{"N"}} sort keys(%FileChanges))
    {
        if(not $FileChanges{$Format}{"Total"}) {
            next;
        }
        $Report .= "<a name='".$FormatInfo{$Format}{"Anchor"}."'></a>\n";
        $Report .= "<h2>".$FormatInfo{$Format}{"Title"}." (".$FileChanges{$Format}{"Total"}.")</h2><hr/>\n";
        $Report .= "<table cellpadding='3' cellspacing='0' class='summary'>\n";
        $Report .= "<tr><th>File</th><th>Status</th><th>HTML<br/>Diff</th><th>Detailed<br/>Report</th></tr>\n";
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
            $Report .= "<td class='left f_path$Color1\'>".$File."</td>\n";
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
            if(my $Link = $Info{"Diff"})
            {
                if($Link eq "empty") {
                    $Report .= "<td$Join></td>\n";
                }
                else {
                    $Report .= "<td$Join><a href='".$Link."' style='color:Blue;'>diff</a></td>\n";
                }
                
            }
            else {
                $Report .= "<td$Join></td>\n";
            }
            if(my $Link = $Info{"Report"})
            {
                if($Link eq "empty") {
                    $Report .= "<td$Join></td>\n";
                }
                else {
                    $Report .= "<td$Join><a href='".$Link."' style='color:Blue;'>report</a></td>\n";
                }
            }
            else {
                $Report .= "<td$Join></td>\n";
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
    open(FILE, ">>".$Path) || die ("can't open file \'$Path\': $!\n");
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
    open (FILE, ">".$Path) || die ("can't open file \'$Path\': $!\n");
    print FILE $Content;
    close(FILE);
}

sub readFile($)
{
    my $Path = $_[0];
    return "" if(not $Path or not -f $Path);
    open (FILE, $Path);
    local $/ = undef;
    my $Content = <FILE>;
    close(FILE);
    return $Content;
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
    if($_[0]=~/\A(.*)[\/\\]+[^\/\\]*[\/\\]*\Z/) {
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

sub cmd_find($$$$)
{ # native "find" is much faster than File::Find (~6x)
  # also the File::Find doesn't support --maxdepth N option
  # so using the cross-platform wrapper for the native one
    my ($Path, $Type, $Name, $MaxDepth) = @_;
    return () if(not $Path or not -e $Path);
    $Path = abs_path($Path);
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

sub getFormat($)
{
    my $Path = $_[0];
    return "" if(not $Path);
    if(defined $Cache{"getFormat"}{$Path}) {
        return $Cache{"getFormat"}{$Path};
    }
    return ($Cache{"getFormat"}{$Path}=getFormat_($Path));
}

sub getFormat_($)
{
    my $Path = $_[0];
    my ($Dir, $Name) = separate_path($Path);
    if(-l $Path) {
        return "SYMLINK";
    }
    elsif(-d $Path) {
        return "DIR";
    }
    elsif($Name=~/\.deb\Z/i)
    { # Deb package
        return "DEB";
    }
    elsif($Name=~/\.(src\.rpm|srpm)\Z/i)
    { # SRPM package
        return "SRPM";
    }
    elsif($Name=~/\.rpm\Z/i)
    { # RPM package
        return "RPM";
    }
    elsif($Name=~/\.(h|hh|hp|hxx|hpp|h\+\+|tcc)\Z/i)
    { # Header file
        return "HEADER";
    }
    elsif($Name=~/\.(cpp|cxx|c\+\+)\Z/i)
    { # Source file
        return "CPP_SRC";
    }
    elsif($Name=~/\.(c)\Z/i)
    { # Source file
        return "C_SRC";
    }
    elsif($Name=~/\.(so)[0-9\-\.\_]*\Z/i)
    { # Shared library
        return "SHLIB";
    }
    elsif($Name=~/\.(a)\Z/i)
    { # Static library
        return "STLIB";
    }
    elsif($Name=~/\.(txt)\Z/i)
    { # Text
        return "TEXT";
    }
    elsif($Name=~/\.(la)\Z/i)
    { # Libtool
        return "LIBTOOL";
    }
    elsif($Name=~/\.(desktop)\Z/i)
    { # Desktop
        return "DESKTOP";
    }
    elsif($Name=~/\.(ps|eps)\Z/i)
    { # Libtool
        return "PS";
    }
    elsif((($Name=~/\.(gz|xz|lzma)\Z/i or $Name=~/\.(\d)\Z/i)
    and $Dir=~/\/(man\d*)(\/|\Z)/)
    or ($Name=~/\.(\d)\Z/i and $Dir=~/\/(doc|docs)(\/|\Z)/))
    { # Manual pages
        return "MANPAGE";
    }
    elsif($Name=~/\.(pc|pc\.in)\Z/i)
    { # Manual pages
        return "PKGCONFIG";
    }
    elsif($Name=~/\A(license|copyright|copying)\Z/i)
    { # Manual pages
        return "LICENSE";
    }
    elsif($Name=~/\.($ARCHIVE_EXT)\Z/i)
    { # Archives
        return "ARCHIVE";
    }
    elsif($Name=~/\.(dox)(\.in|)\Z/i)
    { # Doxygen
        return "DOXYGEN";
    }
    elsif($Name=~/\AMakefile\.(am|in)(\.in|)\Z/i
    or $Name=~/\Aconfigure\.(ac)\Z/i)
    { # Automake
        return "AUTOMAKE";
    }
    elsif($Name=~/\A(Makefile)\Z/i
    or $Name=~/\.(mk)\Z/i)
    { # Makefiles
        return "MAKEFILE";
    }
    elsif($Name=~/\A(CMakeLists\.txt)\Z/i
    or $Name=~/\.(cmake)\Z/i)
    { # Cmake
        return "CMAKE";
    }
    elsif($Name=~/\.(xbel)\Z/i)
    { # Bookmarks
        return "XBEL";
    }
    elsif($Name=~/\.(sgml)\Z/i)
    { # SGML
        return "SGML";
    }
    elsif($Name=~/\.(m4)\Z/i)
    { # M4
        return "M4";
    }
    elsif($Name=~/\.(html|htm)\Z/i)
    { # HTML Pages
        return "HTML";
    }
    elsif($Name=~/\.(xml)(\.in|)\Z/i)
    { # XML
        return "XML";
    }
    elsif($Name=~/\.(css)\Z/i)
    {
        return "CSS";
    }
    elsif($Name=~/\.(prm|par|ff)\Z/i)
    {
        return "PARAM";
    }
    elsif($Name=~/\.(f|for|f90|f95)\Z/i)
    { # Fortran
        return "F_SRC";
    }
    elsif($Name=~/\.(sh|csh)\Z/i)
    { # Shell
        return "SHELL";
    }
    elsif($Name=~/\.(pl|pm)\Z/i)
    { # Perl
        return "PERL";
    }
    elsif($Name=~/\.(py)(\.in|)\Z/i)
    { # Python
        return "PYTHON";
    }
    elsif($Name=~/\.(rb)\Z/i)
    { # Ruby
        return "RUBY";
    }
    elsif($Name=~/\.(java)\Z/i)
    { # Java
        return "JAVA";
    }
    elsif($Name=~/\.(gmo|po|pot)\Z/i)
    { # Gettext
        return "GETTEXT";
    }
    elsif($Name=~/\.(png|jpg|gif)\Z/i)
    { # Images
        return "IMAGE";
    }
    elsif($Name=~/\.(spec)(\.in|)\Z/i)
    { # Spec-files
        return "SPEC";
    }
    elsif($Name=~/\.(sxd)\Z/i)
    { # OpenOffice
        return "OOO";
    }
    elsif($Name=~/\.(patch)\Z/i)
    { # Patch
        return "PATCH";
    }
    elsif($Name=~/\.(vcxproj|vcproj|vcprojin|vcxproj\.filters|vcxproj\.filtersin|sln)\Z/i
    or $Name=~/\.(def|defs|rc|rc\.in|msc|msc\.in|win32)\Z/i)
    { # MSVC++
        return "MSVC";
    }
    elsif(-f $Path)
    {
        my $Type = getType($Path);
        if($Type=~/shell/i) {
            return "SHELL";
        }
        elsif($Type=~/perl/i) {
            return "PERL";
        }
        elsif($Type=~/python/i) {
            return "PYTHON";
        }
        elsif($Type=~/ruby/i) {
            return "RUBY";
        }
        elsif($Type=~/java/i) {
            return "JAVA";
        }
        elsif($Type=~/HTML/i) {
            return "HTML";
        }
        elsif($Type=~/XML/i) {
            return "XML";
        }
        elsif($Type=~/SGML/i) {
            return "SGML";
        }
        elsif($Type=~/gettext/i) {
            return "GETTEXT";
        }
        elsif($Type=~/text/i) {
            return "TEXT";
        }
        elsif($Type=~/executable/i) {
            return "EXE";
        }
        elsif($Type=~/shared object/i) {
            return "SHLIB";
        }
        elsif($Type=~/compressed/i) {
            return "ARCHIVE";
        }
    }
    return "OTHER";
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
            my @Contents = listDir($CPath);
            if($#Contents==0 and -d $CPath."/".$Contents[0])
            {
                $FName = cut_path_prefix($FName, $Contents[0]);
            }
        }
        my $SubDir = "$TMP_DIR/xcontent$Version/$FName";
        $PackageFiles{$Version}{$FName} = $File;
        if(getFormat($File) eq "ARCHIVE")
        { # go into archives
            unpackArchive($File, $SubDir);
            my @Contents = listDir($SubDir);
            my $G = "";
            if($#Contents==0 and -d $SubDir."/".$Contents[0])
            { # libsample-x.y.z.tar.gz/libsample-x.y.z
                $G = get_filename($File)."/".$Contents[0];
                $SubDir .= "/".$Contents[0];
            }
            foreach my $SubFile (cmd_find($SubDir, "", "", ""))
            { # search for all files in archive
                my $SFName = cut_path_prefix($SubFile, $SubDir);
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

sub unpackArchive($$)
{
    my ($Pkg, $OutDir) = @_;
    mkpath($OutDir);
    my $Cmd = "";
    if($Pkg=~/\.(tar\.gz|tgz|tar\.Z)\Z/)
    { # TAR.GZ, TGZ, TAR.Z
        $Cmd = "tar -xzf $Pkg --directory=$OutDir";
    }
    elsif($Pkg=~/\.tar\.bz2\Z/)
    { # TAR.BZ2
        $Cmd = "tar -xjf $Pkg --directory=$OutDir";
    }
    elsif($Pkg=~/\.(tar\.xz|txz)\Z/)
    { # TAR.XZ
        $Cmd = "tar -Jxf $Pkg --directory=$OutDir";
    }
    elsif($Pkg=~/\.tar\Z/)
    { # TAR
        $Cmd = "tar -xf $Pkg --directory=$OutDir";
    }
    elsif($Pkg=~/\.zip\Z/i)
    { # ZIP
        $Cmd = "unzip $Pkg -d $OutDir";
    }
    elsif($Pkg=~/\.jar\Z/)
    { # JAR
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
    $Group{"Format"}{$Format} = 1;
    if($Format eq "DEB")
    { # Deb package
        if(not checkCmd("dpkg-deb")) {
            exitStatus("Not_Found", "can't find \"dpkg-deb\"");
        }
        mkpath($CPath);
        system("dpkg-deb --extract $Path $CPath");
        if($?) {
            exitStatus("Error", "can't extract package d$Version");
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
            exitStatus("Error", "can't extract package d$Version");
        }
        ($Attributes{"Version"}, $Attributes{"Name"}, $Attributes{"Arch"}) = split(",", readRPM($Path, "--queryformat \%{version},\%{name},\%{arch}"));
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
    elsif($Name=~/\A([a-z_\-]+)(.+?)\Z/i)
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
    elsif($_[0]=~/\.(\w+)\Z/) {
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
    $Footer .= " by <a href='".$HomePage{"Dev"}."'>Package Changes Analyzer</a>"; # tool name
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

sub get_Summary()
{
    my $TestInfo = "<h2>Test Info</h2><hr/>\n";
    $TestInfo .= "<table cellpadding='3' cellspacing='0' class='summary'>\n";
    if($CheckMode eq "Group") {
        $TestInfo .= "<tr><th class='left'>Group Name</th><td>".$Group{"Name"}."</td></tr>\n";
    }
    else {
        $TestInfo .= "<tr><th class='left'>Package Name</th><td>".$Group{"Name"}."</td></tr>\n";
    }
    my @Formats = keys(%{$Group{"Format"}});
    $TestInfo .= "<tr><th class='left'>Package Format</th><td>".join(", ", @Formats)."</td></tr>\n";
    if($Group{"Arch"}) {
        $TestInfo .= "<tr><th class='left'>Package Arch</th><td>".$Group{"Arch"}."</td></tr>\n";
    }
    $TestInfo .= "<tr><th class='left'>Version #1</th><td>".$Group{"V1"}."</td></tr>\n";
    $TestInfo .= "<tr><th class='left'>Version #2</th><td>".$Group{"V2"}."</td></tr>\n";
    $TestInfo .= "</table>\n";

    my $TestResults = "<h2>Test Results</h2><hr/>\n";
    $TestResults .= "<table cellpadding='3' cellspacing='0' class='summary'>\n";
    
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
    if(not ($#Formats==0 and $Formats[0] eq "ARCHIVE")) {
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
    
    my $TotalChanged = 0;
    foreach my $Format (keys(%FileChanges))
    {
        $TotalChanged += $FileChanges{$Format}{"Removed"};
        $TotalChanged += $FileChanges{$Format}{"Changed"};
    }
    my $Verdict = "";
    if($TotalChanged)
    {
        $Verdict = "<span style='color:Red;'><b>Incompatible</b></span>";
        $RESULT{"compat"} = "Incompatible";
    }
    else
    {
        $Verdict = "<span style='color:Green;'><b>Compatible</b></span>";
        $RESULT{"compat"} = "Compatible";
    }
    $TestResults .= "<tr><th class='left'>Verdict</th><td>$Verdict</td></tr>\n";
    $TestResults .= "</table>\n";
    
    my $FileChanges = "<a name='Files'></a><h2>Changes In Files</h2><hr/>\n";
    $FileChanges .= "<table cellpadding='3' cellspacing='0' class='summary'>\n";
    $FileChanges .= "<tr><th>File Type</th><th>Total</th><th>Added</th><th>Removed</th><th>Changed</th></tr>\n";
    foreach my $Format (sort {$FormatInfo{$b}{"N"}<=>$FormatInfo{$a}{"N"}} sort keys(%FormatInfo))
    {
        if(not $FileChanges{$Format}{"Total"}) {
            next;
        }
        $FileChanges .= "<tr>\n";
        $FileChanges .= "<td class='left'>".$FormatInfo{$Format}{"Descr"}."</td>\n";
        foreach ("Total", "Added", "Removed", "Changed")
        {
            my $Link = "0";
            if($FileChanges{$Format}{$_}>0) {
                $Link = "<a href='#".$FormatInfo{$Format}{"Anchor"}."' style='color:Blue;'>".$FileChanges{$Format}{$_}."</a>";
            }
            $FileChanges .= "<td>".$Link."</td>\n";
        }
        $FileChanges .= "</tr>\n";
    }
    $FileChanges .= "</table>\n";
    return $TestInfo.$TestResults.get_Report_Headers().get_Report_Deps().$FileChanges;
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

sub createHtmlReport($)
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
}

sub setFormatInfo()
{
    foreach my $Format (keys(%FormatInfo))
    {
        if(not $FormatInfo{$Format}{"Title"})
        {
            $FormatInfo{$Format}{"Title"} = $FormatInfo{$Format}{"Descr"};
            while($FormatInfo{$Format}{"Title"}=~/ ([a-z]+)/)
            {
                my ($W, $UW) = ($1, ucfirst($1));
                $FormatInfo{$Format}{"Title"}=~s/ $W/ $UW/g;
            }
            $FormatInfo{$Format}{"Title"}=~s/(file|page|link|program|bookmark|document)\Z/$1s/i;
            $FormatInfo{$Format}{"Title"}=~s/(librar|director|entr)y\Z/$1ies/i;
        }
        if(not $FormatInfo{$Format}{"Anchor"})
        {
            $FormatInfo{$Format}{"Anchor"} = $FormatInfo{$Format}{"Title"};
            $FormatInfo{$Format}{"Anchor"}=~s/\s//g;
        }
    }
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
    setFormatInfo();
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
        printMsg("WARNING", "different architectures of packages");
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
    createHtmlReport($REPORT_PATH);
    exit($ERROR_CODE{$RESULT{"compat"}});
}

scenario();
