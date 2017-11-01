#!/bin/bash
#
# Synopsis:
#	Show changes between 2 internet-drafts using changebars or html
#	side-by-side diff.
#	
# Usage:
#	rfcdiff [options] file1 file2
#	
#	rfcdiff takes two RFCs or Internet-Drafts in text form as input, and
#	produces output which indicates the differences found in one of various
#	forms, controlled by the options listed below. In all cases, page
#	headers and page footers are stripped before looking for changes.
#	
#	--html		Produce side-by-side .html diff (default)
#	
#	--chbars	Produce changebar marked .txt output
#	
#	--diff		Produce a regular diff output
#	
#	--wdiff		Produce paged wdiff output
#	
#	--hwdiff	Produce html-wrapped coloured wdiff output
#	
#	--oldcolour COLOURNAME	Colour for new file in hwdiff (default is "green")
#	--oldcolor COLORNAME	Color for old file in hwdiff (default is "red")
#
#	--newcolour COLOURNAME	Colour for new file in hwdiff (default is "green")
#	--newcolor COLORNAME	Color for new file in hwdiff (default is "green")
#
#	--larger        Make difference text in hwdiff slightly larger
#	
#	--keep		Don't delete temporary workfiles
#	
#	--version	Show version
#	
#	--help		Show this help
#	
#	--info "Synopsis|Usage|Copyright|Description|Log"
#			Show various info
#	
#	--width	N	Set a maximum width of N characters for the
#			display of each half of the old/new html diff
#	
#	--linenum	Show linenumbers for each line, not only at the
#			start of each change section
#	
#	--body		Strip document preamble (title, boilerplate and
#			table of contents) and postamble (Intellectual
#			Property Statement, Disclaimer etc)
#	
#	--nostrip	Don't strip headers and footers (or body)
#	
#	--ab-diff	Before/After diff, suitable for rfc-editor
#	--abdiff
#	
#	--stdout	Send output to stdout instead to a file
#	
#       --tmpdiff       Path to intermediate diff file
#
#       --prelines N    Set value for diff -U option
#
#       --minimal       Set value for diff -d option
#
#       --ignore-space-change
#                       Ignore changes in the amount of white space.
#
#       --ignore-all-space
#                       Ignore all white space.
#
#       --ignore-blank-lines
#                       Ignore changes whose lines are all blank.
#       
#
# Copyright:
#	-----------------------------------------------------------------
#	
#	Copyright 2002 Henrik Levkowetz
#	
#	This program is free software; you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation; either version 2 of the License, or
#	(at your option) any later version.
#	
#	This program is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#	
#	You should have received a copy of the GNU General Public License
#	along with this program; if not, write to the Free Software
#	Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#
#	-----------------------------------------------------------------
#
# Description:
#
#	The purpose of this program is to compare two versions of an
#	internet-draft, and as output produce a diff in one of several
#	formats:
#	
#		- side-by-side html diff
#		- paged wdiff output in a text terminal
#		- a text file with changebars in the left margin
#		- a simple unified diff output
#	
#	In all cases, internet-draft headers and footers are stripped before
#	generating the diff, to produce a cleaner diff.
#	
#	It is called as
#	
#		rfcdiff first-file second-file
#	
#	The latest version is available from
#		http://tools.ietf.org/tools/rfcdiff/
#

export version="1.41"
export prelines="10"
export basename=$(basename $0)
export workdir=`mktemp -d -t rfcdiff.XXXXXXXX`
export pagecache1="$workdir/pagecache1"
export pagecache2="$workdir/pagecache2"

# ----------------------------------------------------------------------
# Utility to find an executable
# ----------------------------------------------------------------------
lookfor() {
    for b in "$@"; do
	found=$(which "$b" 2>/dev/null)
	if [ -n "$found" ]; then
	    if [ -x "$found" ]; then
		echo "$found"
		return
	    fi
	fi
    done
}

AWK=awk

# ----------------------------------------------------------------------
# Strip headers footers and formfeeds from infile to stdout
# ----------------------------------------------------------------------
strip() {
  $AWK '
				{ gsub(/\r/, ""); }
				{ gsub(/[ \t]+$/, ""); }
				{ pagelength++; }
/\[?[Pp]age [0-9ivx]+\]?[ \t\f]*$/	{
				    match($0, /[Pp]age [0-9ivx]+/);
				    num = substr($0, RSTART+5, RLENGTH-5);
				    print num, outline > ENVIRON["pagecache" ENVIRON["which"]]
				    pagelength = 0;
				}
/\f/				{ newpage=1;
				  pagelength=1;
				}
/\f$/				{
				    # a form feed followed by a \n does not contribute to the
				    # line count.  (But a \f followed by something else does.)
				    pagelength--;
				}
/\f/				{ next; }
/\[?[Pp]age [0-9ivx]+\]?[ \t\f]*$/		{ preindent = indent; next; }

/^ *Internet.Draft.+[12][0-9][0-9][0-9] *$/ && (FNR > 15)	{ newpage=1; next; }
/^ *INTERNET.DRAFT.+[12][0-9][0-9][0-9] *$/ && (FNR > 15)	{ newpage=1; next; }
/^ *Draft.+(  +)[12][0-9][0-9][0-9] *$/	    && (FNR > 15)	{ newpage=1; next; }
/^RFC[ -]?[0-9]+.*(  +).* [12][0-9][0-9][0-9]$/ && (FNR > 15)	{ newpage=1; next; }
/^draft-[-a-z0-9_.]+.*[0-9][0-9][0-9][0-9]$/ && (FNR > 15)	{ newpage=1; next; }
/(Jan|Feb|Mar|March|Apr|April|May|Jun|June|Jul|July|Aug|Sep|Oct|Nov|Dec) (19[89][0-9]|20[0-9][0-9]) *$/ && pagelength < 3  { newpage=1; next; }
newpage && $0 ~ /^ *draft-[-a-z0-9_.]+ *$/ { newpage=1; next; }

/^[ \t]+\[/			{ sentence=1; }
/[^ \t]/			{
				   indent = match($0, /[^ ]/);
				   if (indent < preindent) {
				      sentence = 1;
				   }
				   if (newpage) {
				      if (sentence) {
					 outline++; print "";
				      }
				   } else {
				      if (haveblank) {
					  outline++; print "";
				      }
				   }
				   haveblank=0;
				   sentence=0;
				   newpage=0;

				   line = $0;
				   sub(/^ *\t/, "        ", line);
				   thiscolumn = match(line, /[^ ]/);
				}
/[.:][ \t]*$/			{ sentence=1; }
/\(http:\/\/trustee\.ietf\.org\/license-info\)\./ { sentence=0; }
/^[ \t]*$/			{ haveblank=1; next; }
				{ outline++; print; }
' "$1"
}


# ----------------------------------------------------------------------
# Strip preamble (title, boilerplate and table of contents) and
# postamble (Intellectual Property Statement, Disclaimer etc)
# ----------------------------------------------------------------------
bodystrip() {
    $AWK '
    /^[ \t]*Acknowledgment/		{ inbody = 0; }
    /^(Full )*Copyright Statement$/	{ inbody = 0; }
    /^[ \t]*Disclaimer of Validid/	{ inbody = 0; }
    /^[ \t]*Intellectual Property/	{ inbody = 0; }
    /^Abstract$/			{ inbody = 0; }
    /^Table of Contents$/		{ inbody = 0; }
    /^1.[ \t]*Introduction$/	{ inbody = 1; }

    inbody			{ print; }
    ' "$1"
}


# ----------------------------------------------------------------------
# From two words, find common prefix and differing part, join descriptively
# ----------------------------------------------------------------------
worddiff() {
   $AWK '
BEGIN	{
		w1 = ARGV[1]
		w2 = ARGV[2]
		format = ARGV[3]

		do {
			if (substr(w1,1,1) == substr(w2,1,1)) {
				w1 = substr(w1,2)
				w2 = substr(w2,2)
			} else {
				break;
			}
			prefixlen++;
		} while (length(w1) && length(w2))

		prefix = substr(ARGV[1],1,prefixlen);

		do {
			l1 = length(w1);
			l2 = length(w2);
			if (substr(w1,l1,1) == substr(w2,l2,1)) {
				w1 = substr(w1,1,l1-1)
				w2 = substr(w2,1,l2-1)
			} else {
				break;
			}
		} while (l1 && l2)

		suffix = substr(ARGV[1], prefixlen+length(w1))

		printf format, prefix, w1, w2, suffix;
	}
' "$1" "$2" "$3"
}

# ----------------------------------------------------------------------
# Generate a html page with side-by-side diff from a unified diff
# ----------------------------------------------------------------------
htmldiff() {
   $AWK '
BEGIN	{
           FS = "[ \t,]";

	   # Read pagecache1
	   maxpage[1] = 1
	   pageend[1,0] = 2;
	   while ( getline < ENVIRON["pagecache1"] > 0) {
	      pageend[1,$1] = $2;
	      if ($1+0 > maxpage[1]) maxpage[1] = $1+0;
	   }

	   # Read pagecache2
	   maxpage[2] = 1
	   pageend[2,0] = 2;
	   while ( getline < ENVIRON["pagecache2"] > 0) {
	      pageend[2,$1] = $2;
	      if ($1+0 > maxpage[2]) maxpage[2] = $1+0;
	   }

	   wdiff = ENVIRON["wdiffbin"]
	   base1 = ENVIRON["base1"]
	   base2 = ENVIRON["base2"]
	   optwidth = ENVIRON["optwidth"]
	   optnums =  ENVIRON["optnums"]
	   optlinks = ENVIRON["optlinks"]
	   header(base1, base2)

	   difflines1 = 0
	   difflines2 = 0
	}

function header(file1, file2) {
   url1 = file1;
   url2 = file2;
   if (optlinks) {
      if (file1 ~ /^draft-/) { url1 = sprintf("<a href=\"/html/%s\" style=\"color:#008\">%s</a>", file1, file1); }
      if (file1 ~ /^draft-/) { prev = sprintf("<a href=\"/rfcdiff?url2=%s\" style=\"color:#008; text-decoration:none;\">&lt;</a>", file1); }
      if (file2 ~ /^draft-/) { url2 = sprintf("<a href=\"/html/%s\" style=\"color:#008\">%s</a>", file2, file2); }
      if (file2 ~ /^draft-/) { nxt  = sprintf("<a href=\"/rfcdiff?url1=%s\" style=\"color:#008; text-decoration:none;\">&gt;</a>", file2) }
   }   
   printf "" \
"<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\"> \n" \
"<!-- <!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01 Transitional\" > -->\n" \
"<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\"> \n" \
"<head> \n" \
"  <meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" /> \n" \
"  <meta http-equiv=\"Content-Style-Type\" content=\"text/css\" /> \n" \
"  <title>Diff: %s - %s</title> \n" \
"  <style type=\"text/css\"> \n" \
"    body    { font-family: Arial, sans-serif; font-size:16px; margin: 0.4ex; margin-right: auto; } \n" \
"    table   { width: 100%; } \n" \
"    tr      { } \n" \
"    td      { white-space: pre; font-family: Consolas, \"DejaVu Sans Mono\", \"Droid Sans Mono\", Monaco, Monospace; vertical-align: top; font-size: 0.86em;} \n" \
"    th      { font-size: 0.86em; } \n" \
"    .small  { font-size: 0.6em; font-style: italic; font-family: Verdana, Helvetica, sans-serif; } \n" \
"    .left   { background-color: #EEE; } \n" \
"    .right  { background-color: #FFF; } \n" \
"    .diff   { background-color: #CCF; } \n" \
"    .lblock { background-color: #BFB; } \n" \
"    .rblock { background-color: #FF8; } \n" \
"    .insert { background-color: #8FF; } \n" \
"    .delete { background-color: #ACF; } \n" \
"    .void   { background-color: #FFB; } \n" \
"    .cont   { background-color: #EEE; } \n" \
"    .linebr { background-color: #AAA; } \n" \
"    .lineno { color: red; background-color: #FFF; font-size: 0.7em; text-align: right; padding: 0 2px; } \n" \
"    .elipsis{ background-color: #AAA; } \n" \
"    .left .cont { background-color: #DDD; } \n" \
"    .right .cont { background-color: #EEE; } \n" \
"    .lblock .cont { background-color: #9D9; } \n" \
"    .rblock .cont { background-color: #DD6; } \n" \
"    .insert .cont { background-color: #0DD; } \n" \
"    .delete .cont { background-color: #8AD; } \n" \
"    .stats, .stats td, .stats th { background-color: #EEE; padding: 2px 0; } \n" \
"  </style> \n" \
"</head> \n" \
"<body > \n" \
"  <table border=\"0\" cellpadding=\"0\" cellspacing=\"0\"> \n" \
"  <tr bgcolor=\"#404040\"><th></th><th style=\"color:#fff;\">%s&nbsp;%s&nbsp;</th><th> </th><th style=\"color:#fff;\">&nbsp;%s&nbsp;%s</th><th></th></tr> \n" \
"", file1, file2, prev, url1, url2, nxt;
}

function worddiff(w1, w2) {
   prefixlen = 0;
   word1 = w1;
   do {
      if (substr(w1,1,1) == substr(w2,1,1)) {
	 w1 = substr(w1,2);
	 w2 = substr(w2,2);
      } else {
	 break;
      }
      prefixlen++;
   } while (length(w1) && length(w2));

   prefix = substr(word1,1,prefixlen);

   do {
      l1 = length(w1);
      l2 = length(w2);
      if (substr(w1,l1,1) == substr(w2,l2,1)) {
	 w1 = substr(w1,1,l1-1);
	 w2 = substr(w2,1,l2-1);
      } else {
	 break;
      }
   } while (l1 && l2);

   suffix = substr(word1, prefixlen+length(w1)+1);

   wordpart[0] = prefix;
   wordpart[1] = w1;
   wordpart[2] = w2;
   wordpart[3] = suffix;
}

function numdisplay(which, line) {
    if (optnums && (line != prevline[which])) {
	prevline[which] = line;
	return line-1;
    }
    return "";
}

function fixesc(line) {
#    Making this a no-op for now -- the change in line-breaking
#    "<br><span...>" => "\n" should make this less necessary.
#    line = gensub(/&(<[^>]*>)/, "\\1\\&", "g", line);

#   We still have to handle cases where we have a broken up "&lt;" / "&gt;"
    gsub(/&l<\/span>t;/, "\\&lt;</span>", line);
    gsub(/&g<\/span>t;/, "\\&gt;</span>", line);

    gsub(/&<span class="delete">amp;/, "<span class=\"delete\">\\&", line)
    gsub(/&<span class="insert">amp;/, "<span class=\"insert\">\\&", line)

    gsub(/&<span class="delete">lt;/, "<span class=\"delete\">\\&lt;", line);
    gsub(/&<span class="delete">gt;/, "<span class=\"delete\">\\&gt;", line);
    gsub(/&<span class="insert">lt;/, "<span class=\"insert\">\\&lt;", line);
    gsub(/&<span class="insert">gt;/, "<span class=\"insert\">\\&gt;", line);

    gsub(/&<span class="delete">l<\/span>t;/, "<span class=\"delete\">\\&lt;</span>", line);
    gsub(/&<span class="delete">g<\/span>t;/, "<span class=\"delete\">\\&gt;</span>", line);
    gsub(/&<span class="insert">l<\/span>t;/, "<span class=\"insert\">\\&lt;</span>", line);
    gsub(/&<span class="insert">g<\/span>t;/, "<span class=\"insert\">\\&gt;</span>", line);


    return line;
}

function chunkdiff(chunk) {
   if (difflines1 == 0 && difflines2 == 0) return;

   chunkfile1= sprintf("1/chunk%04d", chunk);
   chunkfile2= sprintf("2/chunk%04d", chunk);
   printf "" > chunkfile1;
   printf "" > chunkfile2;
   for (l = 0; l < difflines1; l++) { print stack1[l] >> chunkfile1; }
   for (l = 0; l < difflines2; l++) { print stack2[l] >> chunkfile2; }
   close(chunkfile1);
   close(chunkfile2);

   cmd1 = sprintf("%s -n -2 -w \"<span class=\\\"delete\\\">\"  -x \"</span>\" %s %s", wdiff, chunkfile1, chunkfile2);
   cmd2 = sprintf("%s -n -1 -y \"<span class=\\\"insert\\\">\"  -z \"</span>\" %s %s", wdiff, chunkfile1, chunkfile2);

   l=0; while (cmd1 | getline > 0) { stack1[l] = fixesc($0); l++; }
   difflines1 = l;
   l=0; while (cmd2 | getline > 0) { stack2[l] = fixesc($0); l++; }
   difflines2 = l;

   close(cmd1);
   close(cmd2);
}

function flush() {
   if (difflines1 || difflines2) {
      difftag++;
      multiline = (difflines1 > 1) || (difflines2 > 1);
      if (multiline && (wdiff != "")) chunkdiff(difftag);

      printf "      <tr><td><a name=\"diff%04d\" /></td></tr>\n", difftag;
      for (l = 0; l < difflines1 || l < difflines2; l++) {
	 if (l in stack1) {
	    line1 = stack1[l];
	    delete stack1[l];
	    linenum1++
	    if (line1 == "")
	       if (optwidth > 0) {
		   line1 = substr("                                                                                                                                                                ",0,optwidth);
	       } else {
		   line1 = "                                                                         ";
	       }
	 } else {
	    line1 = "";
	 }
	 if (l in stack2) {
	    line2 = stack2[l];
	    delete stack2[l];
	    linenum2++;
	    if (line2 == "")
	       if (optwidth > 0) {
		   line2 = substr("                                                                                                                                                                ",0,optwidth);
	       } else {
		   line2 = "                                                                         ";
	       }
	 } else {
	    line2 = "";
	 }

	 if (!multiline || (wdiff == "")) {
	    worddiff(line1, line2);
	    line1 = fixesc(sprintf("%s<span class=\"delete\">%s</span>%s", wordpart[0], wordpart[1], wordpart[3]));
	    line2 = fixesc(sprintf("%s<span class=\"insert\">%s</span>%s", wordpart[0], wordpart[2], wordpart[3]));
	    # Clean up; remove empty spans
	    sub(/<span class="delete"><\/span>/,"", line1);
	    sub(/<span class="insert"><\/span>/,"", line2);
	 }
	 left  = sprintf("<td class=\"lineno\" valign=\"top\">%s</td><td class=\"lblock\">%s</td>", numdisplay(1, linenum1), line1);
	 right = sprintf("<td class=\"rblock\">%s</td><td class=\"lineno\" valign=\"top\">%s</td>", line2, numdisplay(2, linenum2));
	 printf "      <tr>%s<td> </td>%s</tr>\n", left, right;
      }
   }
}

function getpage(which, line) {
    line = line + ENVIRON["prelines"];
    page = "?";
    for (p=1; p <= maxpage[which]; p++) {
	if (pageend[which,p] == 0) continue;
	if (line <= pageend[which,p]) {
	    page = p;
	    break;
	}
    }
    return page;
}

function getpageline(which, line, page) {
    if (page == "?") {
	return line + ENVIRON["prelines"];
    } else {
	if (pageend[which,page-1]+0 != 0) {
	    return line + ENVIRON["prelines"] - pageend[which,page-1] + 3; # numbers of header lines stripped
	} else {
	    return "?";
	}
    }
}

function htmlesc(line) {
    gsub("&", "\\&amp;", line);
    gsub("<", "\\&lt;", line);
    gsub(">", "\\&gt;", line);
    return line;
}

function expandtabs(line) {
    spaces = "        ";
    while (pos = index(line, "\t")) {
	sub("\t", substr(spaces, 0, (8-pos%8)), line);
    }
    return line;
}

function maybebreakline(line,    width) {
    width = optwidth;
    new = "";
    if (width > 0) {
	line = expandtabs(line);
	while (length(line) > width) {
	    new = new htmlesc(substr(line, 1, width)) "\n";
	    line = substr(line, width+1);
	}
    }
    line = new htmlesc(line) ;
    return line;
}

/^@@/	{
	   linenum1 = 0 - $2;
	   linenum2 = 0 + $4;
	   diffnum ++;
	   if (linenum1 > 1) {
	      printf "      <tr><td class=\"lineno\"></td><td class=\"left\"></td><td> </td><td class=\"right\"></td><td class=\"lineno\"></td></tr>\n";
	      page1 = getpage(1,linenum1);
	      page2 = getpage(2,linenum2);
	      if (page1 == "?") {
		 posinfo1 = sprintf("<a name=\"part-l%s\" /><small>skipping to change at</small><em> line %s</em>", diffnum, getpageline(1, linenum1, page1));
	      } else {
		 posinfo1 = sprintf("<a name=\"part-l%s\" /><small>skipping to change at</small><em> page %s, line %s</em>", diffnum, page1, getpageline(1, linenum1, page1));
	      }

	      if (page2 == "?") {
		 posinfo2 = sprintf("<a name=\"part-r%s\" /><small>skipping to change at</small><em> line %s</em>", diffnum, getpageline(2, linenum2, page2));
	      } else {
		 posinfo2 = sprintf("<a name=\"part-r%s\" /><small>skipping to change at</small><em> page %s, line %s</em>", diffnum, page2, getpageline(2, linenum2, page2));
	      }

	      printf "      <tr bgcolor=\"#c0c0c0\" ><td></td><th>%s</th><th> </th><th>%s</th><td></td></tr>\n", posinfo1, posinfo2;
	   }
	}

/^---/	{  next; }
/^[+][+][+]/	{  next; }
/^[ ]/	{
	   line = substr($0, 2);
	   line = maybebreakline(line);

	   flush();
	   linenum1++;
	   linenum2++;
	   printf "      <tr><td class=\"lineno\" valign=\"top\">%s</td><td class=\"left\">%s</td><td> </td>", numdisplay(1, linenum1), line;
	   printf "<td class=\"right\">%s</td><td class=\"lineno\" valign=\"top\">%s</td></tr>\n", line, numdisplay(2, linenum2);
	   diffcount1 += difflines1
	   difflines1 = 0
	   diffcount2 += difflines2
	   difflines2 = 0
	}
/^-/	{
	   line = substr($0, 2);
	   line = maybebreakline(line);

	   stack1[difflines1] = line;
	   difflines1++;
	}
/^[+]/	{
	   line = substr($0, 2);
	   line = maybebreakline(line);

	   stack2[difflines2] = line;
	   difflines2++;
	}

END	{
	   flush();
	   printf("\n" \
"     <tr><td></td><td class=\"left\"></td><td> </td><td class=\"right\"></td><td></td></tr>\n" \
"     <tr bgcolor=\"#c0c0c0\"><th colspan=\"5\" align=\"center\"><a name=\"end\">&nbsp;%s. %s change block(s).&nbsp;</a></th></tr>\n" \
"     <tr class=\"stats\"><td></td><th><i>%s line(s) changed or deleted</i></th><th><i> </i></th><th><i>%s line(s) changed or added</i></th><td></td></tr>\n" \
"     <tr><td colspan=\"5\" align=\"center\" class=\"small\"><br/>This html diff was produced by rfcdiff %s</td></tr>\n" \
"   </table>\n" \
"   </body>\n" \
"   </html>\n", diffnum?"End of changes":"No changes", difftag, diffcount1, diffcount2, ENVIRON["version"]);
	}
' "$1"
}

# ----------------------------------------------------------------------
# Generate before/after text output from a context diff
# ----------------------------------------------------------------------
abdiff() {
$AWK '
BEGIN	{
	   # Read pagecache1
	   maxpage[1] = 1
	   pageend[1,0] = 2;
	   while ( getline < ENVIRON["pagecache1"] > 0) {
	      pageend[1,$1] = $2;
	      if ($1+0 > maxpage[1]) maxpage[1] = $1+0;
	   }

	   # Read pagecache2
	   maxpage[2] = 1
	   pageend[2,0] = 2;
	   while ( getline < ENVIRON["pagecache2"] > 0) {
	      pageend[2,$1] = $2;
	      if ($1+0 > maxpage[2]) maxpage[2] = $1+0;
	   }

	   base1 = ENVIRON["base1"]
	   base2 = ENVIRON["base2"]

	   section = "INTRODUCTION";
	   para = 0;

	}
/^\+\+/ {
	   next;
	}
/^\-\-/ {
	   next;
	}
/^ Appendix ./	{
	   section = $1 " " $2;
	   para = 0;
	}
/^  ? ? ?[0-9]+(\.[0-9]+)*\.? /	{
	   section = "Section " $1;
	   para = 0;
	}
/^ ?$/	{
	   if (inpara) {
	      printf "\n%s, paragraph %s:\n", section, para;
	      print "OLD:\n"
	      print oldpara
	      print "NEW:\n"
	      print newpara
	   }
	   oldpara = "";
	   newpara = "";
	   para ++;
	   inpara = 0
	}
/^ ./	{
	   oldpara = oldpara $0 "\n"
	   newpara = newpara $0 "\n"
	}
/^\-/	{
	   sub(/^./, " ");
	   oldpara = oldpara $0 "\n"
	   inpara++;
	}
/^\+/	{
	   sub(/^./, " ");
	   newpara = newpara $0 "\n"
	   inpara++;
	}
END	{
	   if (inpara) {
	      printf "\n%s, paragraph %s:\n", section, para;
	      print "OLD:\n"
	      print oldpara
	      print "NEW:\n"
	      print newpara
	   }	
	}
'
}


# ----------------------------------------------------------------------
# Utility to extract keyword info
# ----------------------------------------------------------------------
extract() {
    $AWK -v keyword="$1" '
	BEGIN {
	    # print "Keyword", keyword;
	}
	/^# [A-Z]/ {
	    # print "New key", $2;
	    if ($2 == keyword ":" ) { output=1; } else { output=0; }
	    # print "Output", output;
	}
	/^#\t/	{
	    # print "Content", output, $0;
	    if ( output ) {
		sub(/^#/,"");
		print;
	    }
	}
	{
	    next;
	}

    ' "$2"
}


# ----------------------------------------------------------------------
# Utility for error exit
# ----------------------------------------------------------------------
die() {
   echo $*;
   exit 1;
}

# ----------------------------------------------------------------------
# Process options
# ----------------------------------------------------------------------

# Default values
opthtml=1; optdiff=0; optchbars=0; optwdiff=0; optnowdiff=0;
optkeep=0; optinfo=0; optwidth=0;  optnums=0;  optbody=0; optabdiff=0;
optstrip=1; opthwdiff=0; optlinks=0;
optoldcolour="red"; optnewcolour="green"; optlarger=""
optstdout=0;
opttmpdiff=0; tmpdiff=$workdir/diff;

while [ $# -gt 0 ]; do
   case "$1" in
      --html)   opthtml=1; optdiff=0; optchbars=0; optwdiff=0; opthwdiff=0; optabdiff=0;;
      --diff)   opthtml=0; optdiff=1; optchbars=0; optwdiff=0; opthwdiff=0; optabdiff=0;;
      --chbars) opthtml=0; optdiff=0; optchbars=1; optwdiff=0; opthwdiff=0; optabdiff=0;;
      --wdiff)  opthtml=0; optdiff=0; optchbars=0; optwdiff=1; opthwdiff=0; optabdiff=0;;
      --hwdiff) opthtml=0; optdiff=0; optchbars=0; optwdiff=0; opthwdiff=1; optabdiff=0;;
      --changes)opthtml=0; optdiff=0; optchbars=0; optwdiff=0; opthwdiff=0; optabdiff=1;;
      --abdiff)	opthtml=0; optdiff=0; optchbars=0; optwdiff=0; opthwdiff=0; optabdiff=1;;
      --ab-diff)opthtml=0; optdiff=0; optchbars=0; optwdiff=0; opthwdiff=0; optabdiff=1;;
      --rfc-editor-diff)opthtml=0; optdiff=0; optchbars=0; optwdiff=0; opthwdiff=0; optabdiff=1;;
      --version)echo -e "$basename\t$version"; exit 0;;
      --nowdiff)optnowdiff=1;;
      --keep)	optkeep=1;;
      --info)	optinfo=1; keyword=$2; shift;;
      --help)	optinfo=1; keyword="Usage";;
      --width)	optwidth=$2; shift;;
      --oldcolor)     optoldcolour=$2; shift;;
      --oldcolour)    optoldcolour=$2; shift;;
      --newcolor)     optnewcolour=$2; shift;;
      --newcolour)    optnewcolour=$2; shift;;
      --larger)       optlarger='size="+1"';;
      --linenum)optnums=1;;
      --body)	optbody=1;;
      --nostrip)optstrip=0; optbody=0;;
      --stdout) optstdout=1;;
      --links)  optlinks=1;;
      --ignore-space-change) optnospacechange=1;;
      --ignore-all-space) optignorewhite=1;;
      --ignore-blank-lines) optignoreblank=1;;
      --wdiff-args) optwdiffargs=$2; shift;;
      --tmpdiff) opttmpdiff=1; tmpdiff=$2; shift;;
      --prelines)  export prelines=$2; shift;;
      --minimal) optminimal=1;;
      --)	shift; break;;

      -v) echo "$basename $version"; exit 0;;
      -*) echo "Unrecognized option: $1";
	  exit 1;;
      *)  break;;
   esac
   shift
done

export optwidth
export optnums
export optlinks

# ----------------------------------------------------------------------
# Determine output file name. Maybe output usage and exit.
# ----------------------------------------------------------------------
#set -x

if [ $optinfo -gt 0 ]; then
   extract $keyword $0
   exit
fi
if [ $# -ge 2 ]; then
   if [ "$1" = "$2" ]; then
      echo "The files are the same file"
      exit
   fi
   export base1=$(basename "$1")
   export base2=$(basename "$2")
   outbase=$(worddiff "$base2" "$base1" "%s%s-from-%s")
else
   extract Usage $0
   exit 1
fi


# ----------------------------------------------------------------------
# create working directory.
# ----------------------------------------------------------------------
mkdir $workdir/1 || die "$0: Error: Failed to create temporary directory '$workdir/1'."
mkdir $workdir/2 || die "$0: Error: Failed to create temporary directory '$workdir/2'."

# ----------------------------------------------------------------------
# Copy files to a work directory
# ----------------------------------------------------------------------
cp "$1" $workdir/1/"$base1"
cp "$2" $workdir/2/"$base2"


# ----------------------------------------------------------------------
# Maybe strip headers/footers from both files
# ----------------------------------------------------------------------

if [ $optstrip -gt 0 ]; then
   export which=1
   strip $workdir/1/"$base1" > $workdir/1/"$base1".stripped
   mv -f $workdir/1/"$base1".stripped $workdir/1/"$base1"
   export which=2
   strip $workdir/2/"$base2" > $workdir/2/"$base2".stripped
   mv -f $workdir/2/"$base2".stripped $workdir/2/"$base2"
fi

# ----------------------------------------------------------------------
# Maybe do html quoting
# ----------------------------------------------------------------------

if [ $opthwdiff -gt 0 ]; then
   sed -e 's/&/&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' $workdir/1/"$base1" > $workdir/1/"$base1".quoted
   mv -f $workdir/1/"$base1".quoted $workdir/1/"$base1"
   sed -e 's/&/&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' $workdir/2/"$base2" > $workdir/2/"$base2".quoted
   mv -f $workdir/2/"$base2".quoted $workdir/2/"$base2"
fi

# ----------------------------------------------------------------------
# Maybe strip preamble (title, boilerplate and table of contents) and
# postamble (Intellectual Property Statement, Disclaimer etc)
# ----------------------------------------------------------------------
if [ $optbody -gt 0 ]; then
   bodystrip $workdir/1/"$base1" > $workdir/1/"$base1".stripped
   mv $workdir/1/"$base1".stripped $workdir/1/"$base1"
   bodystrip $workdir/2/"$base2" > $workdir/2/"$base2".stripped
   mv $workdir/2/"$base2".stripped $workdir/2/"$base2"
fi

# ----------------------------------------------------------------------
# Get output file name
# ----------------------------------------------------------------------
if [ "$3" ]; then
  outfile="$3"
else
    if [ $opthtml -gt 0 ]; then
      outfile=./"$outbase".diff.html
    fi
    if [ $optchbars -gt 0 ]; then
      outfile=./"$outbase".chbar
    fi
    if [ $optdiff -gt 0 ]; then
      outfile=./"$outbase".diff
    fi
    if [ $optabdiff -gt 0 ]; then
      outfile=./"$outbase".changes
    fi
    if [ $opthwdiff -gt 0 ]; then
      outfile=./"$outbase".wdiff.html
    fi
fi
if [ "$outfile" ]; then
   tempout=./$(basename "$outfile")
fi

# ----------------------------------------------------------------------
# Check if we can use wdiff for block diffs
# ----------------------------------------------------------------------
if [ $optnowdiff -eq 0 ]; then
   wdiffbin=$(lookfor wdiff)
   export wdiffbin
fi

# ----------------------------------------------------------------------
# Do diff
# ----------------------------------------------------------------------

origdir=$PWD
cd $workdir
if cmp 1/"$base1" 2/"$base2" >/dev/null; then
   echo ""
   echo "The files are identical."
fi

if [ $opthtml -gt 0 ]; then
   diff ${optignoreblank:+-B} ${optminimal:+-d} ${optnospacechange:+-b} ${optignorewhite:+-w} -U $prelines 1/"$base1" 2/"$base2" | tee $tmpdiff | htmldiff > "$tempout"
fi
if [ $optchbars -gt 0 ]; then
   diff -Bwd -U 10000 1/"$base1" 2/"$base2" | tee $tmpdiff | grep -v "^-" | tail -n +3 | sed 's/^+/|/' > "$tempout"
fi
if [ $optdiff -gt 0 ]; then
   diff -Bwd -U $prelines 1/"$base1" 2/"$base2" | tee $tmpdiff > "$tempout"
fi
if [ $optabdiff -gt 0 ]; then
   diff -wd -U 1000 1/"$base1" 2/"$base2" | tee $tmpdiff | abdiff
fi
if [ $optwdiff -gt 0 ]; then
   wdiff -a $optwdiffargs 1/"$base1" 2/"$base2"
fi
if [ $opthwdiff -gt 0 ]; then
    echo "<html><head><title>wdiff "$base1" "$base2"</title></head><body>"	>  "$tempout"
    echo "<pre>"								>> "$tempout"
    wdiff -w "<strike><font color='$optoldcolour' $optlarger>" -x "</font></strike>"	\
          -y "<strong><font color='$optnewcolour' $optlarger>" -z "</font></strong>"	\
	  1/"$base1" 2/"$base2"							>> "$tempout"
    echo "</pre>"								>> "$tempout"
    echo "</body></html>"							>> "$tempout"
fi

if [ $optstdout -gt 0 ]; then
  cat "$tempout"
  rm  "$tempout"
else
  cd "$origdir"; if [ -f $workdir/"$tempout" ]; then mv $workdir/"$tempout" "$outfile"; fi
fi

if [ $optkeep -eq 0 ]; then
   if [ -f $pagecache1 ]; then rm $pagecache1; fi
   if [ -f $pagecache2 ]; then rm $pagecache2; fi
   rm -fr $workdir/1
   rm -fr $workdir/2
   if [ -f $tmpdiff ]; then
      if [ $opttmpdiff -eq 0 ]; then
          rm $tmpdiff
      fi
   fi
   rm -f $workdir/$tmpdiff
   rmdir $workdir
else
   cd /tmp
   tar czf $basename-$$.tgz $basename-$$
   echo "
   Temporary workfiles have been left in $workdir/, and packed up in $workdir.tgz"
fi

