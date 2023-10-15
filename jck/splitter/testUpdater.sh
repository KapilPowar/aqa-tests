#!/usr/bin/env bash

callSplitter(){
    TARGET_TO_SPLIT="${WORKSPACE}/test/JCK-compiler-${JDK_VERSION}/tests/lang"
    mkFileName="${WORKSPACE}/jck.mk"

    for ((i=0; i<${#keys[@]}; i++)); do
        key="${keys[i]}"
        value="${values[i]}"

        #echo "Key: $key, Value: $value"
        if [[ "$key" == "VERIFIER" && "$JDK_VERSION" == "8d" ]]; then
            echo "No need to create PR for --- $key"
        else
            TARGET="${TARGET_TO_SPLIT}/${key}"
            if [[ "$key" == "VERIFIER" ]]; then
                TARGET="${WORKSPACE}/test/JCK-runtime-${JDK_VERSION}/tests/vm/verifier/instructions"
            fi
            SCRIPT="./splitter.sh ${TARGET} ${value}"
            if [ "$key" == "CLSS" ]; then
                key="CLASS"
            fi
            logFileName="${key}.log"
            #echo "logFileName $logFileName" 
            ${SCRIPT} > ${logFileName}
            #return_status=$?
            lastLine=$(grep -E "COMPILER_LANG_${key}_TESTS_GROUP|VERIFIER_INSTRUCTIONS_TESTS_GROUP" "$logFileName" | tail -n 1)
            # Check if the last line is present in the target file
            #echo $lastLine
            if grep -qF "$lastLine" "$mkFileName"; then
            echo "No need to create PR for --- $key"
            else
            #echo "We need to create PR for --- $key"
            testClassList+=("$key")
            PR_NEEDED=true
            fi
        fi
    done
    # for value in "${testClassList[@]}"; do
    #     echo $value
    # done
    echo "PR_NEEDED=$PR_NEEDED"
    echo "${testClassList[@]}"
}


WORKSPACE=$1
JDK_VERSION=$2

keys=("ANNOT" "CLSS" "CONV" "DASG" "EXPR" "INTF" "LMBD" "NAME" "TYPE" "STMT" "VERIFIER")
values=("5" "10" "5" "5" "11" "5" "5" "5" "5" "5" "4")
PR_NEEDED=false
testClassList=()
callSplitter
# if [ -n "$testClassList" ]; then
#   echo "testClassList is not empty: $testClassList"
# else
#   echo "testClassList is empty"
# fi


