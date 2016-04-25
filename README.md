Introduction
------------

This repository contains our ongoing work on reasoning about WordPress plugins.
This makes use of [PHP Analysis in Rascal (PHP AiR)][phpair]; please see the
instructions there for setting up PHP AiR, which must be used to run the code
in this project.

Downloading the Corpus
----------------------

The corpus we are currently using consists of thousands of WordPress plugins,
downloaded from the WordPress plugin repository. Because of this, we have
not attempted to include a direct download of the corpus. Instead, we have
provided a shell script, `fetchCorpus.sh`, available in the `extract`
subdirectory. This can be run as follows:

    cd ~/PHPAnalysis
    mkdir plugins
    cd plugins
    <project-dir>/extract/fetchCorpus.sh

where `<project-dir>` is the location where this project has been cloned.
Assuming the script has been made executable, this will checkout each plugin
used in our analysis, at the correct revision, and place it into the `plugins`
directory.

Building the Corpus
-------------------

More information will be posted soon about building the corpus and constructing
text search indexes for the corpus items.
