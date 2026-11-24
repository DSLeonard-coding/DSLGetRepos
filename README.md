# DSLGetRepos  D.S. Leonard, 2026, MIT with attribution

The best of submodules and package management combined. (uv-like package management in C++)

Provides one-liner git-submodule drop-in replacement in-tree-wrapper to CPM package management, ie dependency repo fetching.

**This is still super ALPHA, rapid early draft stage, and anything may change, and I may force push.***  

The original CPM.cmake managed by Lars Melchior, is included with this from: https://github.com/cpm-cmake/cpm.cmake

DSLGetRepo provides the wrapper for submodule drop-in replacement, in-place build, sha-locking, multi-build-locking and related "one-line" functionality.

Uses download-only so sources are compatible with any use.

## Features:
### Core CPM features inherited:
- Auto-download of dependencies at cmake configure time.  
- No submodule updates to forget when switching branches.
- Provides transitive dependency handling, locking, and overrides.
- Like submodules, can pull from any kind of source, doesn't have to be cmake or CPM. 

### DSLGetRepos features
- One line configuration per repo. 
- Supports in-tree build/devel workflow.
- Optional explicit destination paths allow drop-in replacement for git submodules without changing any directory structure.  **Ie all your symlinks or script references to the source still work!!** (only exceptions are rare commands that can't follow symlinks).
- Sources are only downloaded once, to top-level dependencies/<NAME> by default (or ${DGR_REPOS_DIR} if defined), duplicates are symlinked.
- Along with accompanying scripts, provides follow-braches, relock-commits-to-sha, workflow for transitive/duplicate deps. (inspired by uv lockfiles)
- Development override by adding .developing file to any source dir.
- Auto-handles/creates .gitignore entries of dependency directories.
- Supports Multi-build environments like Clion, with single download (arranges mutex to control concurrent access to CPMAddPackage to avoid git conflicts).

## Installation:  
   This is the project manager so you can't project manage it, maybe a cookie cutter someday lol.
      (or better, something like https://github.com/DSLeonard-coding/DSLeonard-pylaunch)

From your projects root just do this to copy in the files:
```
wget -qO- https://raw.githubusercontent.com/DSLeonard-coding/DSLGetRepos/master/install.sh | sh
```

## Usage

in your CMakeLists.txt just do this to load it:
```
     include(cmake/CPM/DSLGetRepo.cmake)
```

 Then just load a dependency project, Ex, the other .cmake files included in DSLeonard-cmake:
```
     dsl_get_repo( DSLeonard-cmake https://github.com/DSLeonard-coding/DSLeonard-cmake master)
```
- The branch can be a tag, sha, or any ref, but the provided locking tools are meant to work well with branch refs.
- The first parameter is the name.  The important thing is that all projects including the package agree on the name. They don't have to agree on the source or even reference, but the name associates them.  Convention is to use the cmake project name in CMakeLists.txt.

 "Returns:" Source directory in ${DSLeonard-cmake_SOURCE_DIR}
  In general you can use that with add_subdirectory etc.  In this example it's used for other includes.
```
     set(DSL_CMAKE_PATH "${DSLeonard-cmake_SOURCE_DIR}/cmake/DSL/")
     include("${DSL_CMAKE_PATH}/cern/Geant4_Target.cmake")
```
but if you need to pin the path (to where you had your submodule for example) see [explicit path parameter](#explicit-path-parameter) below.


-By default the sources go in `dependencies/`.  For example:  `dependencies/DSleonard-cmake`  
-Even if a lower project has a DSLGetRepo  dep it will go in the top level dependencies.  
-Non DSLGetRepo CPM deps should still work fine, but will use their own build directories, usually in your build directories.  
-Non CPM deps from any git repo also work fine.  You will just get the files in dependencies/my_deps, and the path to them.
-See full CPM documentation.

### Explicit path parameter and migrating from submodules.

You can set the source path that your project expects to see the source in explicitly by adding an extra parameter to dsl_get_repo.  It takes either an absolute path or a path relative to the CMakeLists.txt that made or outsourced the call.  Each project in the dep chain can set its own, and each will get a link to the source at that location.  In all cases, the source will exist at the ${<NAME>_SOURCE_DIR} location returned.  With explicit paths, you can just set where you want a symlink to be so that it aligns with your project structure.  

Alternatively you can set a per-project dependency directory with 
```
set(DGR_${PROJECT_NAME}_REPOS_DIR  "somepath"}
```
and you will get symlinks to all your deps in there.  This replaces the default of dependencies/   For the top level project this is equal to DGR_REPOS_DIR by default, and the real source is installed there, not a symlink.

The code refuses to replace a populated directory, so if migrating from a submodule you first must git submodule deinit and git rm the directory, before loading the code there with dsl_get_repo. 


### Explicit source directories
The explicit path mechanisms to dsl_get_repo tell where to link sources into the source trees, but you can also separately control where the real sources live.  Set all of these before calling dsl_get_repo().

CPM has a default override mechanism to set source paths.  
set CPM_<NAME>_SOURCE to a path to use that as an override for the source location.  This is an alternative to adding .developing to the fetched location.
For this though, you have to put the source there yourself, with a git clone for example. 

DSLGetRepos also provides the ${DGR_REPOS_DIR} CACHE variable that defines a single directory where all your sources can be found.  This has the advantage that dsl_get_repo will auto-install into them or auto update them all if they do not exist or are not marked with .developing.  To avoid subproject overriding it, it can only be set with -DDGR_REPOS_DIR="somepath"  or an explicit cache set

```
set(DGR_REPOS_DIR "/some/path" CACHE PATH "Where dsl_get_repo stores real clones")
```

This can be one way to switch back and forth between external development sources and internal sources. But you still need to add .developing to every source path.



### Optional Variables:
Accepts ${DGR_${PROJECT_NAME}_REPOS_DIR} (defined before calling dsl_get_repo, defines where all deps will be included or linked for this project).  
Default is dependencies/


## Updating, developing and locking

You can add an empty .developing file to any source directory.  

This will override updates to that source, allowing development in place.  In the long run it can be better to have external 
repos for development override, because in this workflow you will need to commit and backup untracked files before removing the .developing.  But this provides a low-friction way to get all the dep repos and make quick commits/pushes if/when needed.  Also, so long as you auto-update your lock shas and pull the latest commit from the branch your locks are tracking, you end up testing the same shas you're committing anyway.  So it can be a viable long-term development solution.

### locking and lock updating

You should run update-lock.sh at least once before setting .developing in a new source directory.  If a source is overridden (by .developing file or otherwise), the lock file information provided CPM will not include the source repo, so we can't update it.  Once you have locked once though, we keep the source location around unless you edit the package-lock.cmake by hand.

Use the included update-lock.sh or directly lock-deps.py.  The shell script will add any new dependencies to your package-lock.cmake and will update shas to the latest versions on tracked branches.  The python script can merge without updating.  It works best with uv.  Use -h option for help.

to install uv:
```
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env
```


