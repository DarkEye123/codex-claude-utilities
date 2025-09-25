#!/bin/bash
# This script removes local branches that have been deleted from the remote repository.
git branch -vv | grep ': gone]' | awk '{print $1}' | xargs -r git branch -D