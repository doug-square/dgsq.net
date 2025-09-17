#!/bin/bash

#git subtree push --prefix public origin gh-pages

pushd public
git stage .
git commit -m "Update"
git push
popd

git commit
git push
