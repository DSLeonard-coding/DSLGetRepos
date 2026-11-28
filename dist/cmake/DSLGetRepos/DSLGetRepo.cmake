include_guard(GLOBAL)
#DSLGetRepo.cmake  D.S. Leonard, 2026
#
#Provides one-liner in-tree wrapper to CPM project management, ie dependency repo fetching.
# See github.com/DSLeonard-coding/DSLGetRepos   for documentation.

#a better guard that prevents other versions from loading in subprojects:
get_property(_dgr_already_loaded GLOBAL PROPERTY DSL_GET_REPO_LOADED)
if(_dgr_already_loaded)
    return()
endif()
set_property(GLOBAL PROPERTY DSL_GET_REPO_LOADED TRUE)

include("${CMAKE_CURRENT_LIST_DIR}/CPM.cmake")
set(CPM_INCLUDE_ALL_IN_PACKAGE_LOCK ON)
set(CPM_LOCK_FILE "${CMAKE_SOURCE_DIR}/package-lock.cmake" CACHE FILEPATH "CPM lock file")
CPMUsePackageLock(${CPM_LOCK_FILE})

option(DGR_LINK_RELATIVE "Create relative symlinks (survive moving the tree)" ON)

# Legacy: lock files written by older versions recorded DOWNLOAD_ONLY inside the entries.
# This version only reads GIT_REPOSITORY and GIT_TAG from an entry, so this only protects
# plain (non-dsl) CPMAddPackage(NAME x) callers.  Safe to delete once locks are regenerated.
function(_dgr_strip_all_download_only)
    get_cmake_property(vars VARIABLES)
    foreach(var IN LISTS vars)
        if(var MATCHES "^CPM_DECLARATION_.+" AND NOT "${${var}}" STREQUAL "")
            set(decl "${${var}}")
            list(FIND decl DOWNLOAD_ONLY idx)
            if(NOT idx EQUAL -1)
                math(EXPR val_idx "${idx} + 1")
                list(REMOVE_AT decl ${idx} ${val_idx})
                set(${var} "${decl}" PARENT_SCOPE)
            endif()
        endif()
    endforeach()
endfunction()

_dgr_strip_all_download_only()

# Sets ${result} (in the caller) to TRUE if `dir` is a working git clone, else FALSE.
function(is_git_repo dir result)
    set(${result} FALSE PARENT_SCOPE)
    if(EXISTS "${dir}/.git")
        # checks if it's really a valid repo.
        execute_process(COMMAND git rev-parse --git-dir
                WORKING_DIRECTORY "${dir}"
                RESULT_VARIABLE rc OUTPUT_QUIET ERROR_QUIET)
        if(rc EQUAL 0)
            set(${result} TRUE PARENT_SCOPE)
        endif()
    endif()
endfunction()


# Add `path` to the .gitignore next to it, if not already there.
# A trailing slash only matches directories, so a symlink gets an entry without one.
function(git_ignore_entry path)
    get_filename_component(parent "${path}" DIRECTORY)
    get_filename_component(name "${path}" NAME)
    set(gitignore "${parent}/.gitignore")

    if(IS_SYMLINK "${path}")
        set(entry "/${name}")
    else()
        set(entry "/${name}/")
    endif()

    set(lines "")
    if(EXISTS "${gitignore}")
        file(STRINGS "${gitignore}" lines)
    endif()
    if(NOT "${entry}" IN_LIST lines)
        file(APPEND "${gitignore}" "${entry}\n")
    endif()
endfunction()


# Make `link` a symlink to `target`. No-op if they are already the same place.
function(make_symlink link target)
    get_filename_component(real_target "${target}" REALPATH)
    get_filename_component(real_link   "${link}"   REALPATH)
    if(real_link STREQUAL real_target)
        return()
    endif()

    if(IS_SYMLINK "${link}")                     # stale or dangling link: replace
        file(REMOVE "${link}")
    elseif(EXISTS "${link}")
        set(children "")
        if(IS_DIRECTORY "${link}")
            file(GLOB children LIST_DIRECTORIES true "${link}/*" "${link}/.*")
        endif()
        if(IS_DIRECTORY "${link}" AND NOT children)
            file(REMOVE_RECURSE "${link}")       # empty dir, e.g. uninitialised submodule
        else()
            message(FATAL_ERROR
                    "dsl_get_repo: cannot symlink ${link} -> ${target}: "
                    "path exists and is not an empty directory or symlink. "
                    "Remove it (or deinit the old submodule) and reconfigure.")
        endif()
    endif()

    get_filename_component(link_parent "${link}" DIRECTORY)
    file(MAKE_DIRECTORY "${link_parent}")

    if(DGR_LINK_RELATIVE)
        file(RELATIVE_PATH link_target "${link_parent}" "${target}")
    else()
        set(link_target "${target}")
    endif()

    file(CREATE_LINK "${link_target}" "${link}" SYMBOLIC RESULT rc)
    if(NOT "${rc}" STREQUAL "0")
        message(FATAL_ERROR
                "dsl_get_repo: failed to create symlink ${link} -> ${link_target}: ${rc}\n"
                "(On Windows this needs Developer Mode or elevated privileges.)")
    endif()
endfunction()


# _dsl_repo_impl(NAME REPO TAG DOWNLOAD_ONLY_MODE [DIR] CPM_ARGS)
#
# The real source (the "home") is always ${DGR_REPOS_DIR}/${NAME}, or the user's
# CPM_<NAME>_SOURCE (CMake variable or environment) if set.  It is returned in
# ${NAME}_SOURCE_DIR.
#
# DIR (or, if not given, DGR_<PROJECT_NAME>_REPOS_DIR}/${NAME} when that variable is set)
# is where the calling project wants the repo to appear.  If that is not the home,
# it becomes a symlink to the home.  Relative paths are relative to the calling
# CMakeLists.txt (CMAKE_CURRENT_SOURCE_DIR).
#
# CPM sees three names for one package:
#   ${NAME}        a facade.  Registered with CPM after the fetch, with the fetched
#                  directories stored, so a plain CPMAddPackage(NAME ${NAME}) elsewhere
#                  returns early with the right ${NAME}_SOURCE_DIR.  CPM never fetches it.
#   ${NAME}_FETCH  the DOWNLOAD_ONLY clone/update of ${home}.  Always DOWNLOAD_ONLY, always
#                  FORCE (CPM's override, declaration and find_package handling are bypassed;
#                  this file does them).  Lock recording is off for it.
#   ${NAME}_BUILD  the add_subdirectory (dsl_add_repo only).
#
# Package identity is ${NAME}. A package-lock entry for ${NAME} overrides the
# call site's REPO and TAG (canonical_url / effective_tag) and is written to
# the build's lock entry.
#
# fetch_url is the local URL used to actually reach the repo (for example,
# using SSH instead of HTTPS locally) without changing what gets recorded in
# the lock file.

# Two phases:
#  1. FETCH (locked): the ${NAME}_FETCH clone/update of ${home}, plus symlink and
#     .gitignore upkeep.  Nothing here recurses into other dsl_* calls, so the lock
#     can never be re-entered.
#  2. ADD (unlocked, dsl_add_repo only): registered with CPM as ${NAME}_BUILD pointing
#     at the directory CPM actually fetched.  add_subdirectory recurses into the
#     dependency's own dsl_* calls here, with no lock held, so circular dependencies
#     work: CPM registers the name before add_subdirectory, so the cycle stops at its
#     "already added" return.
#
# OPTIONS: only dsl_add_repo applies them, and the first add wins.
function(_dsl_repo_impl NAME REPO TAG DOWNLOAD_ONLY_MODE)
    # where real sources live: only a cache value (-DDGR_REPOS_DIR=...) can move it
    if(DEFINED CACHE{DGR_REPOS_DIR})
        get_filename_component(store "$CACHE{DGR_REPOS_DIR}" ABSOLUTE BASE_DIR "${CMAKE_SOURCE_DIR}")
    else()
        set(store "${CMAKE_SOURCE_DIR}/deps")
    endif()

    # CPM's own handling is bypassed for ${NAME}_FETCH, so read the environment form of
    # the override here, as CPM would
    if(NOT DEFINED CPM_${NAME}_SOURCE AND DEFINED ENV{CPM_${NAME}_SOURCE})
        file(TO_CMAKE_PATH "$ENV{CPM_${NAME}_SOURCE}" CPM_${NAME}_SOURCE)
    endif()

    # where the real source lives: user override, else the one top-level store
    if(NOT "${CPM_${NAME}_SOURCE}" STREQUAL "")
        set(home "${CPM_${NAME}_SOURCE}")
        set(overridden TRUE)
    else()
        set(home "${store}/${NAME}")
        set(overridden FALSE)
    endif()

    # where the caller wants it to appear (a symlink unless it is the home)
    cmake_parse_arguments(PARSE_ARGV 4 _dgr "" "DIR" "")

    if(DEFINED _dgr_DIR)
        set(wanted "${_dgr_DIR}")
    elseif(DEFINED PROJECT_NAME AND DEFINED DGR_${PROJECT_NAME}_REPOS_DIR)
        set(wanted "${DGR_${PROJECT_NAME}_REPOS_DIR}/${NAME}")
    else()
        set(wanted "${home}")
    endif()

    # relative paths mean relative to the calling CMakeLists.txt
    get_filename_component(home   "${home}"   ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    get_filename_component(wanted "${wanted}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")

    foreach(arg IN LISTS _dgr_UNPARSED_ARGUMENTS)
        if(arg STREQUAL "SOURCE_DIR" OR arg STREQUAL "DOWNLOAD_ONLY"
                OR arg STREQUAL "NAME" OR arg STREQUAL "GIT_REPOSITORY"
                OR arg STREQUAL "GIT_TAG")
            message(FATAL_ERROR
                    "dsl_get_repo: Direct pass through of CPM ${arg} arg is not supported")
        endif()
    endforeach()

    # Handle the top-level project asked for by name.  It is already being configured
    # from CMAKE_SOURCE_DIR: nothing to fetch, and add_subdirectory on it would recurse.
    # Treat it as an already-added dependency: register it with CPM, link it where
    # the caller wants it.
    if(DEFINED CMAKE_PROJECT_NAME AND "${NAME}" STREQUAL "${CMAKE_PROJECT_NAME}")
        set(root_home "${CMAKE_SOURCE_DIR}")

        # `wanted` defaults to "where it already is", so a link is made only if DIR or
        # DGR_<PROJECT_NAME>_REPOS_DIR asked for one.
        if(NOT DEFINED _dgr_DIR AND NOT (DEFINED PROJECT_NAME
                AND DEFINED DGR_${PROJECT_NAME}_REPOS_DIR))
            set(wanted "${root_home}")
        endif()

        if(NOT wanted STREQUAL root_home)
            make_symlink("${wanted}" "${root_home}")
            git_ignore_entry("${wanted}")
        endif()

        if(NOT "${NAME}" IN_LIST CPM_PACKAGES)
            CPMRegisterPackage("${NAME}" "${CMAKE_PROJECT_VERSION}")
            cpm_store_fetch_properties("${NAME}" "${root_home}" "${CMAKE_BINARY_DIR}")
        endif()

        set(${NAME}_SOURCE_DIR "${root_home}" PARENT_SCOPE)
        set(${NAME}_BINARY_DIR "${CMAKE_BINARY_DIR}" PARENT_SCOPE)
        set(${NAME}_ADDED NO PARENT_SCOPE)
        set(CPM_LAST_PACKAGE_NAME "${NAME}" PARENT_SCOPE)
        return()
    endif()

    # Identity: a lock entry for NAME wins over the call (URL and tag).  Other fields of the
    # entry are not applied; the call's own extra args are.
    set(canonical_url "${REPO}")
    set(effective_tag "${TAG}")
    if(NOT "${CPM_DECLARATION_${NAME}}" STREQUAL "")
        cmake_parse_arguments(_dgr_decl "" "GIT_REPOSITORY;GIT_TAG" "" ${CPM_DECLARATION_${NAME}})
        if(NOT "${_dgr_decl_GIT_REPOSITORY}" STREQUAL "")
            set(canonical_url "${_dgr_decl_GIT_REPOSITORY}")
        endif()
        if(NOT "${_dgr_decl_GIT_TAG}" STREQUAL "")
            set(effective_tag "${_dgr_decl_GIT_TAG}")
        endif()
    endif()

    # Access: how we reach the repo.  Today the same as the identity; this is the seam
    # for choosing a different transport (ssh) locally without touching what gets recorded.
    set(fetch_url "${canonical_url}")

    # ------------------------------------------------------------------
    # Phase 1: FETCH, under the cross-process lock
    # ------------------------------------------------------------------
    get_filename_component(_home_parent "${home}" DIRECTORY)
    get_filename_component(_home_name   "${home}" NAME)
    set(_lockfile "${_home_parent}/.${_home_name}.lock")

    # serialize across processes (parallel CLion profiles).  GUARD FUNCTION is a safety
    # net for the FATAL_ERROR paths; the normal path releases explicitly below.
    file(LOCK "${_lockfile}" GUARD FUNCTION TIMEOUT 300 RESULT_VARIABLE locked)
    if(NOT locked EQUAL 0)
        message(FATAL_ERROR "dsl_get_repo: timed out waiting for ${_lockfile}")
    endif()

    # CPM must not record the _FETCH and _BUILD names.  Remember whether recording is on,
    # and write the entry for NAME ourselves.  (Function scope: callers are unaffected.)
    set(_record_in_lock "${CPM_PACKAGE_LOCK_ENABLED}")
    set(CPM_PACKAGE_LOCK_ENABLED FALSE)

    set(first_registration FALSE)
    if(NOT "${NAME}" IN_LIST CPM_PACKAGES)
        set(first_registration TRUE)
    endif()

    if(first_registration)
        if(overridden OR EXISTS "${home}/.developing")
            # user-supplied or in-development source: CPM must not touch it, so no
            # repo/tag is passed and nothing is cloned or updated
            CPMAddPackage(
                    NAME ${NAME}_FETCH
                    SOURCE_DIR "${home}"
                    DOWNLOAD_ONLY YES
                    FORCE YES)
        else()
            # anything else CPM manages, so it updates when the locks (shas) say to
            is_git_repo("${home}" valid_clone)
            if(NOT valid_clone)
                # folder missing or unusable: drop this build dir's stale record, then clone
                if(DEFINED FETCHCONTENT_BASE_DIR)
                    set(_fc_base "${FETCHCONTENT_BASE_DIR}")
                else()
                    set(_fc_base "${CMAKE_BINARY_DIR}/_deps")
                endif()
                string(TOLOWER "${NAME}_fetch" _lower_fetch)
                file(REMOVE_RECURSE "${_fc_base}/${_lower_fetch}-subbuild")
            endif()

            CPMAddPackage(
                    NAME ${NAME}_FETCH
                    GIT_REPOSITORY ${fetch_url}
                    GIT_TAG ${effective_tag}
                    SOURCE_DIR "${home}"
                    DOWNLOAD_ONLY YES
                    FORCE YES        # skip CPM's override, declaration and find_package handling
                    ${_dgr_UNPARSED_ARGUMENTS})
        endif()

        # the facade: NAME is now "added" as far as CPM and everyone else can tell
        CPMGetPackageVersion("${NAME}_FETCH" _fetch_version)
        CPMRegisterPackage("${NAME}" "${_fetch_version}")
        cpm_store_fetch_properties("${NAME}" "${${NAME}_FETCH_SOURCE_DIR}" "${${NAME}_FETCH_BINARY_DIR}")
        set(${NAME}_SOURCE_DIR "${${NAME}_FETCH_SOURCE_DIR}")
        set(${NAME}_BINARY_DIR "${${NAME}_FETCH_BINARY_DIR}")
        set(${NAME}_ADDED YES)

        # what CPM would have recorded for NAME: the identity, not the access URL
        if(_record_in_lock)
            cpm_add_to_package_lock(${NAME}
                    NAME ${NAME}
                    GIT_REPOSITORY ${canonical_url}
                    GIT_TAG ${effective_tag}
                    ${_dgr_UNPARSED_ARGUMENTS})
        endif()

        set_property(GLOBAL PROPERTY DGR_FETCHED_${NAME} TRUE)
    else()
        # already registered (by us earlier, or by a plain CPMAddPackage): reuse its record
        cpm_get_fetch_properties("${NAME}")
        set(${NAME}_ADDED NO)
    endif()

    if(EXISTS "${home}/.developing")
        message(WARNING "The override is set by the existence of ${home}/.developing\n Delete it to allow auto update." )
    endif()

    if(NOT overridden)
        git_ignore_entry("${home}")
    endif()

    if(NOT wanted STREQUAL home)
        make_symlink("${wanted}" "${home}")
        git_ignore_entry("${wanted}")
    endif()

    # Release now, before anything can recurse.
    file(LOCK "${_lockfile}" RELEASE)

    # ------------------------------------------------------------------
    # Phase 2: ADD, no lock held  (CPM_PACKAGE_LOCK_ENABLED is still off in this scope)
    # ------------------------------------------------------------------
    set(pkg "${NAME}")
    get_property(fetched GLOBAL PROPERTY DGR_FETCHED_${NAME})
    if(NOT DOWNLOAD_ONLY_MODE AND fetched)
        # Add what was actually fetched (override, local source)
        set(src "${${NAME}_SOURCE_DIR}")
        if(src STREQUAL "" OR NOT IS_DIRECTORY "${src}")
            message(WARNING "dsl_add_repo: nothing to add for ${NAME} (no source dir)")
        else()
            set(pkg "${NAME}_BUILD")

            # Pin the binary dir to the one phase 1 reported, so it is known before the
            # add starts (a cycle re-entering mid-add can't see CPM's own record yet).
            set(bin_args "")
            if(NOT "${${NAME}_BINARY_DIR}" STREQUAL "")
                set(bin_args BINARY_DIR "${${NAME}_BINARY_DIR}")
            endif()

            # CPM registers ${pkg} before add_subdirectory, so a cycle back to this name
            # hits CPM's "already added" return instead of recursing.  First add wins.
            CPMAddPackage(
                    NAME ${pkg}
                    SOURCE_DIR "${src}"
                    ${bin_args}
                    DOWNLOAD_ONLY NO
                    FORCE YES        # skip CPM's find_package(${pkg}) lookup
                    ${_dgr_UNPARSED_ARGUMENTS})
            if(${pkg}_ADDED)
                # restore the find_package(NAME) redirect that a plain add would make
                cpm_create_module_file(${NAME})
            endif()
        endif()
    endif()

    # Keep phase 1's values unless phase 2 has real ones (empty inside a cycle).
    if(NOT pkg STREQUAL NAME)
        foreach(var SOURCE_DIR BINARY_DIR)
            if(NOT "${${pkg}_${var}}" STREQUAL "")
                set(${NAME}_${var} "${${pkg}_${var}}")
            endif()
        endforeach()
        set(${NAME}_ADDED "${${pkg}_ADDED}")
    endif()

    # pass results to the caller under the plain name
    foreach(var SOURCE_DIR BINARY_DIR ADDED)
        set(${NAME}_${var} "${${NAME}_${var}}" PARENT_SCOPE)
    endforeach()
    set(CPM_LAST_PACKAGE_NAME "${NAME}" PARENT_SCOPE)
endfunction()

# DOWNLOAD_ONLY mode: fetch only, no add_subdirectory, any OPTIONS are not applied
function(dsl_get_repo NAME REPO TAG)
    _dsl_repo_impl("${NAME}" "${REPO}" "${TAG}" YES ${ARGN})
    foreach(var SOURCE_DIR BINARY_DIR ADDED)
        set(${NAME}_${var} "${${NAME}_${var}}" PARENT_SCOPE)
    endforeach()
    set(CPM_LAST_PACKAGE_NAME "${CPM_LAST_PACKAGE_NAME}" PARENT_SCOPE)
endfunction()

# Fetch and add targets into the build (no DOWNLOAD_ONLY YES)
function(dsl_add_repo NAME REPO TAG)
    _dsl_repo_impl("${NAME}" "${REPO}" "${TAG}" NO ${ARGN})
    foreach(var SOURCE_DIR BINARY_DIR ADDED)
        set(${NAME}_${var} "${${NAME}_${var}}" PARENT_SCOPE)
    endforeach()
    set(CPM_LAST_PACKAGE_NAME "${CPM_LAST_PACKAGE_NAME}" PARENT_SCOPE)
endfunction()