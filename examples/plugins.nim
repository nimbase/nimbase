import ../src/nimbase/pluginkit

initExtension dp:
  ## A simple example of how to create plugins for other
  ## languages using Nimbase toolkit
  name: "example"
  version: "0.1.0"

  phpModule do:
    # here we initialize the PHP module and define the
    # functions we want to export to PHP
    proc helloWorld(name: string) =
      ## This comment should be exported as the doc comment for the generated PHP function
      echo "Hello, ", name, " from PHP!"
  
  rubyModule do:
    # here we initialize the Ruby module and define the
    # functions we want to export to Ruby
    proc helloWorld(name: string) =
      echo "Hello, ", name," from Ruby!"

  jsModule do:
    # here we initialize the JavaScript module and define the
    # functions we want to export to JavaScript
    proc helloWorld(name: string) =
      echo "Hello, ", name," from JavaScript", " via N-API!"
  