# DSLGetRepos
D.S. Leonard, 2026, MIT with attribution

Drop-in  "one-liner" git-submodule replacement: An in-tree-wrapper to modern CPM package management for C++, providing fixed submodule-like linked source paths, with added uv-like locking functionality, multi-build file locking, and mixed 
 DOWNLOAD_ONLY calls.

**This is ALPHA, anything may change, even the name and URL, and I may force push, but it works for me. Reports are appreciated***  

The original CPM.cmake managed by Lars Melchior, is included with this from: https://github.com/cpm-cmake/cpm.cmake

DSLGetRepo provides the wrapper for submodule drop-in replacement, in-place build, source directory linking, sha-locking for branch tracking, and parallel build compatibility(mutexes).

Uses download-only by default (options may come), so its compatible with your existing submodule build structures.


## Installation:
This is the project manager so you can't project manage it, maybe a cookie cutter someday lol.
(or better, something like https://github.com/DSLeonard-coding/DSLeonard-pylaunch) )

From your projects root just do this to copy in the files:
```
wget -qO- https://raw.githubusercontent.com/DSLeonard-coding/DSLGetRepos/master/install.sh | sh
```

## Usage

in your CMakeLists.txt just do this to load it:
```
include(cmake/CPM/DSLGetRepo.cmake)
```

Then just load a dependency project, Ex, other userful .cmake files included in DSLeonard-cmake:
```
dsl_add_repo( DSLeonard-cmake https://github.com/DSLeonard-coding/DSLeonard-cmake master OPTIONS "SOMEVAR VALUE")
```
or for ssh access (for **private repos**) use the git syntax:
```
dsl_add_repo( DSLeonard-cmake git@github.com:DSLeonard-coding/DSLeonard-cmake master OPTIONS "SOMEVAR VALUE")
```
(In the future I hope to auto-switch to ssh when needed, so the syntax won't need to change, but there are some difficulties with implementing that. )

or use the wrapper to CPM's DOWNLOAD_ONLY option:
```
dsl_get_repo( DSLeonard-cmake_SRC https://github.com/DSLeonard-coding/DSLeonard-cmake master)

#Optionally add subdirectory or whatever else:
if(TARGET "DSLeonard-cmake")
  #Directory provided by dsl_get_repo via CPM:
  add_subdirectory(${DSLeonard-cmake_SRC_SOURCE_DIR}) 
endif
```

The two commands (get and add version) are identical, except the latter passes `DOWNLOAD_ONLY YES`to CPM, where the former simply calls add_subdirectory automatically, but only the first time it is requested, automatically avoiding duplicate call errors. **Unlike with direct, CPM, you _can_ mix use of these for the same package name!** They both provide the resolved source directory in \<NAME>_SOURCE_DIR, and the former provides the binary build directory (second parameter to add_subdirectory) in \<NAME>_BINARY_DIR, where \<NAME> is the first argument to dsl_get_repo. 

dsl_get_repo is the more direct git-submodule replacement, and is necessary for packages that don't have a CMakeLists.txt, but dsl_add_repo avoids duplicate add_subdirectory calls without you needing an if(TARGET MYTARGET) guard. Notably dsl_add_repo loses access to variables that are PARENT_SCOPE in the add_subdirectory call, but you can only do that from one place anyway, even with git-submodules. (future possibilities exist).

**If you need to fix the path (to where you had your submodule for example)** see [explicit path parameter](#explicit-path-parameter-and-migrating-from-submodules) below.

For the particular package in the example, the add_subdirectory does nothing of value, and I just use the resulting source variable like this:
```
#example usage of source path:
set(DSL_CMAKE_PATH "${DSLeonard-cmake_SOURCE_DIR}/cmake/DSL/")
include("${DSL_CMAKE_PATH}/cern/Geant4_Target.cmake")
```

- The branch can be a tag, sha, or any ref, but it's more flexible to set a branch and use [locking](#locking-and-lock-updating) to point to a commit.
- The first parameter is the name.  The important thing is that all projects that include the package agree on the name. They don't have to agree on the source or even reference, but the name associates them.  Convention is to use the cmake project name in CMakeLists.txt.

- By default, the sources go in `dependencies/`.  For example:  `dependencies/DSleonard-cmake`
- Even if a lower project has a DSLGetRepo  dep it will go in the top level dependencies, but be sym-linked to all.
- Deps that are not themselves DSLGetRepo or CPM enabled should still work fine, but will use their own build directories, usually in your build directories.
- Non-CPM deps from any git repo also work fine.  You will just get the files in dependencies/my_deps, and the path to them.
- See full CPM documentation.







<!-- START doctoc generated TOC please keep comment here to allow auto update -->

**Table of Contents**  *generated with [DocToc](https://github.com/ktechhub/doctoc)*

<!---toc start-->

* [Installation:](#installation)
* [Usage](#usage)
* [Motivation and Overview](#motivation-and-overview)
* [Core CPM features inherited:](#core-cpm-features-inherited)
* [DSLGetRepos features](#dslgetrepos-features)
* [Explicit path parameter and migrating from submodules.](#explicit-path-parameter-and-migrating-from-submodules)
* [Explicit source directories](#explicit-source-directories)
* [Optional Variables and passthrough arguments to CPM/FetchContent/ExternalProject_Add() and add_subdirectory()](#optional-variables-and-passthrough-arguments-to-cpmfetchcontentexternalproject_add-and-add_subdirectory)
* [Developing overrides](#developing-overrides)
* [locking and lock updating](#locking-and-lock-updating)
  * [Tracking development branches.](#tracking-development-branches)
  * [Installing uv](#installing-uv)
* [Different calls, same repo:](#different-calls-same-repo)

<!---toc end-->

<!-- END doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->


## Motivation and Overview
CPM does most of the work here, but DSLGetRepos adds fixed symlink paths relative to each dependency tree individually, and improved branch-following and sha updating.   The first part is a mixed blessing.  For modularity and simplified installs, it's better not to have tight coupling between the directory structures of your projects and their dependencies, which is generally the cmake philosophy.  But a) not everything you want to include is even cmake-based and b) not everything is ideal.    **By fixing symlinks to sources within each dependency we create a stable source layout that matches any legacy submodule layout, or any non-cmake needs, and reduce headache of distributing a directory variable to everything that needs it.** 

For what it's worth, CPM is relatively new, around 2019, based on cmake FetchContent that only arrived in 2018.

## Core CPM features inherited:
- Auto-download of dependencies at cmake configure time, including any recursive submodules of deps.  
- No submodule updates to forget when switching branches, because the build system does it.
- Provides transitive dependency handling, locking(reproducible deps per commit), and overrides, without duplication or multiple versions of deps.
- Like submodules, can pull from any kind of source, doesn't have to be cmake or CPM. 

## DSLGetRepos features
- One line configuration per repo. 
- Supports in-tree build/devel workflow.
- Optional explicit destination paths allow drop-in replacement for git submodules without changing any directory structure.  **Ie all your symlinks or script references to the source still work!!** (only exceptions are rare commands that can't follow symlinks).
- Sources are only downloaded once, to top-level dependencies/\<NAME> by default (or ${DGR_REPOS_DIR} if defined), duplicates are symlinked.
- Along with accompanying scripts, provides follow-branches, relock-commits-to-sha, workflow for transitive/duplicate deps. (IE commits lock dependencies to specific git sha's, but between commits you can auto-update those shas along the branch: inspired by uv lockfiles but also by `git submodules update --remote --recursive`)
- Add .developing file to any dependency directory to develop the dependency repo in-place and prevent automated updates. (be careful to test your development on committed lockfile commit sha's though) 
- Auto-handles/creates .gitignore entries of dependency directories.
- Supports Multi-build environments like Clion, with single download (arranges mutex to control concurrent access to CPMAddPackage to avoid git conflicts).
- Allows mixed use of DOWNLOAD_ONLY CPM option.



## Explicit path parameter and migrating from submodules.

You can set the source path that your project expects to see the source in explicitly by adding an extra DIR parameter to dsl_get_repo. like this: 

```
dsl_get_repo( 
      DSLeonard-cmake 
      https://github.com/DSLeonard-coding/DSLeonard-cmake 
      master 
      DIR "DSLeonard-cmake"
      )
```
It takes either an absolute path or a path relative to the CMakeLists.txt that made or outsourced the call (`\$\{CMAKE\_CURRENT\_SOURCE\_DIR}`). Each project in the dep chain can set its own, and each will get a link to the source at that location.  In all cases, the source will exist at the `\$\{\<NAME\>_SOURCE_DIR}` location returned.  With explicit paths, you can just set where you want a symlink to be so that it aligns with your project structure.  



Alternatively you can set a per-project dependency directory with 
```
set(DGR_${PROJECT_NAME}_REPOS_DIR  "somepath"
```
and you will get symlinks to all your deps in there.  This replaces the default of dependencies/   For the top level project this is equal to `DGR_REPOS_DIR` by default, and the real source is installed there, not a symlink.

The code refuses to replace a populated directory, so if migrating from a submodule you first must git submodule deinit and git rm the directory, before loading the code there with dsl_get_repo. 


## Explicit source directories
The explicit path mechanisms to dsl_get_repo tell where to link sources into the source trees, but you can also separately control where the real sources live.  Set all of these before calling dsl_get_repo().

CPM has a default override mechanism to set source paths.  
set `CPM_\<NAME>_SOURCE` to a path to use that as an override for the source location.  This is an alternative to adding .developing to the fetched location.
For this though, you have to put the source there yourself, with a git clone for example. 

DSLGetRepos also provides the `${DGR_REPOS_DIR}` CACHE variable that defines a single directory where all your sources can be found.  This has the advantage that dsl_get_repo will auto-install into them or auto update them all if they do not exist or are not marked with .developing.  To avoid subproject overriding it, it can only be set with -DDGR_REPOS_DIR="somepath"  or an explicit cache set

```
set(DGR_REPOS_DIR "/some/path" CACHE PATH "Where dsl_get_repo stores real clones")
```

This can be one way to switch back and forth between external development sources and internal sources. But you still need to add .developing to every source path.



## Optional Variables and passthrough arguments to CPM/FetchContent/ExternalProject_Add() and add_subdirectory()

Because dsl_add_repo is a function, your variables are not in scope when add_subdirectory is called.  CPM has an option called OPTIONS that dsl_add_repo passes through, and it takes a list of pairs of NAME VALUE and sets VALUE to the variable NAME before calling add subdirectory.  Because DSLGetRepos now allows mixed calls for DOWNLOAD_ONLY, it can be easiyer just to use dsl_get_repo, and o the add_subdirectory call yourself.

As discussed elsewhere the scripts accept `\$\{DGR\_\$\{PROJECT_NAME\}\_REPOS_DIR\}` (defined before calling dsl_get_repo, defines where all deps will be included or linked for this project).  
Default is `dependencies/`,   Also    `\$\{DGR\_REPOS_DIR}` defines where the real sources will exist or download to when called as the top project.  They will still be linked to `\$\{DGR\_$\{PROJECT_NAME}\_REPOS_DIR}` or the explicit DIR option for all projects. 

Extra parameters to dsl_get_repo pass through to CPM, which passes through extra parameters to `FetchContent_populate()` which further passes to `ExternalProject_Add()`.  It's turtles all the way down.  


## Developing overrides

You can add an empty .developing file to any source directory.  

This will override updates to that source, allowing development in place.   In this workflow you will need to commit and backup untracked files before removing the .developing and allowing this means you have to be careful that you test the same versions that you lock in your commits.  But this provides a low-friction way to get all the dep repos and make quick commits/pushes if/when needed.  Also, so long as you auto-update your lock shas and pull the latest commit from the branch that your locks are tracking, you end up testing the same shas you're committing anyway. But for the long run it might be better to have external repos for development override by setting CPM_<PackageName>_SOURCE_DIR, because.

## locking and lock updating

This could be maybe a separate repo.  The project includes a wrapper script to control dependency locking for CPM, and introduces separate configuration files for tracking and locking.

run the included lock-deps.py as
```
./lock-deps.py -h
```
to see usage.
It requires uv installed, see below.

The sort of quick start is:
```
./lock-deps.py update --configure --build cmake-build-release --all
```
where cmake-build-release should be replaced with your cmake build directory.

This will create a `package-sources.cmake` and a `package-lock.cmake`

You can update source repos or branches in package-soruces.cmake.  Then you can run lock-deps again to update package-locks.cmake to the specific shas to use for the commit you're about to make. Then when anyone checks out this commit, they will get those shas.  If you use --all then all deps will be updated and locked to their latest versions.  If you only want to update some, specify package names instead.


You should run `lock-deps.py` with `sync` or `update`  at least once before setting .developing in a new source directory.  If a source is overridden (by .developing file or otherwise), the lock file information provided by CPM will not include the source repo, so we can't update it automatically.  Once you have locked once though, we keep the source location in package-sources.cmake.  If you get a package-sources.cmake entry with no url or branch you can just edit it by hand once.  The entries are the same as for CPMAddPacakge.

### Tracking development branches.

If you need to track a development branch, just change the branch in package-sources.cmake and update the locks.  That's it.  You should of course probably be committing to a development branch too then. 


### Installing uv
to install uv:
```
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env
```


## Different calls, same repo:

CPM cannot mix DOWNLOAD_ONLY YES calls with normal (implicit add_subdirectory) calls to the same repo NAME.  DSLGetRepo can. It wraps the calls through different package names internally but translates locking/directories and variables to the user.

The first call (and locks or overrides) will determine the download URL and tag.  The first dsl_add_repo call will set the options.
