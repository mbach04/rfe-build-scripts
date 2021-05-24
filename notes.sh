   24  cd rfe-build-scripts/
   25  composer-cli blueprints push RFE.toml 
   26  composer-cli blueprints list
   27  composer-cli compose start RFE rhel-edge-commit
   28  watch composer-cli compose status
   30  composer-cli  compose image a49eb4b8-dbdd-4459-a7a5-b1957ec936ba 
   31  tar xf *.tar
   36  vim RFE.toml 
   38  jq '."ostree-commit"' compose.json
   39  composer-cli blueprints push RFE.toml 
   41  composer-cli compose start-ostree RFE rhel-edge-commit --parent ced023d4a440802e970a878ea55d4a7272a7de5dee4eafb6a8df7a6c5478b446
   42  watch composer-cli compose status
