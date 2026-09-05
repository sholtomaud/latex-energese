## latexmkrc -- build settings for anything that drives this repository
## through latexmk: LaTeX Workshop, TeXShop, a bare `latexmk`, CI.
##
## `make` does not read this file. The Makefile is the reference build and
## passes both of these settings itself; this is here so that an editor's
## build button produces the same thing rather than failing in two ways that
## look like the document's fault.
##
## latexmk reads ./latexmkrc at startup, so this applies when latexmk is
## started from the repository root -- which is what an editor does with a
## workspace open here, adding -cd to descend into docs/.

use Cwd qw(abs_path);
use File::Basename qw(dirname);

## 1. The engine is LuaLaTeX, not pdfLaTeX.
##
## energese.sty loads luacode and calls \directlua: the layout engine *is* a
## Lua program, and pdflatex cannot run it. It does not degrade -- it stops.
##
## Both lines are needed, for different callers. $pdf_mode picks the engine
## when latexmk is left to choose; $pdflatex redefines what the "pdf" rule
## actually runs, so that a caller passing -pdf on the command line (LaTeX
## Workshop's default latexmk arguments do) still gets LuaLaTeX rather than
## overriding the mode back to pdfLaTeX.
$pdf_mode = 4;
$pdflatex = 'lualatex %O %S';
$lualatex = 'lualatex %O %S';

## 2. The package is at the repository root; the documents are not.
##
## docs/article.tex and docs/energese_user_guide.tex say \usepackage{energese},
## and energese.sty, energese-shapes.tex, energese-core.lua and dkjson.lua all
## sit one directory up. Built in place -- which is what -cd does -- TeX looks
## in docs/ and reports `File energese.sty not found', which reads like a
## missing dependency rather than a search path that is one directory short.
##
## Absolute, derived from this file's own location, so it holds wherever
## latexmk is started and whichever directory it descends into.
my $root = dirname(abs_path(__FILE__));
ensure_path('TEXINPUTS', $root);
ensure_path('LUAINPUTS', $root);

## 3. Reproducible output, as the fidelity harness requires (AGENTS.md
## section 3). Without these the PDF differs run to run, and a golden built
## from an editor build would not match one built by `make`.
$ENV{SOURCE_DATE_EPOCH} = '0';
$ENV{FORCE_SOURCE_DATE} = '1';
