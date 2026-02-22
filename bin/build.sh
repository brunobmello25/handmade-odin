#!/bin/bash

#!/bin/bash

mkdir -p ./target

pushd ./target
# odin build ../src -out=./game -vet-packages:main,model -vet-unused -vet-unused-imports -vet-unused-procedures -vet-unused-variables -vet-using-param -vet-using-stmt -debug -error-pos-style:unix
odin build ../src/raylib-handmade -out=./game -debug -error-pos-style:unix
popd
