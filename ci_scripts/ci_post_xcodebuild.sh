#!/bin/zsh
#  ci_post_xcodebuild.sh

if [[ -d "$CI_APP_STORE_SIGNED_APP_PATH" ]]; then
  TESTFLIGHT_DIR_PATH=../TestFlight
  mkdir -p $TESTFLIGHT_DIR_PATH
  echo "" >> $TESTFLIGHT_DIR_PATH/WhatToTest.en-CA.txt
  echo "Last commits:" >> $TESTFLIGHT_DIR_PATH/WhatToTest.en-CA.txt
  git fetch --deepen 6 && git log -6 --pretty=format:"%h %s" | nl -s ". " >> $TESTFLIGHT_DIR_PATH/WhatToTest.en-CA.txt
fi
