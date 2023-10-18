#!/usr/bin/env bash

updateJCKmkFile(){

    sourceFilePath=$1
    tempFile=$(mktemp)

    while IFS= read -r targetLine; do
        if [[  "$targetLine" == *'('* ]]; then
            key=$(echo "$targetLine" | cut -d '(' -f 1 | awk '{$1=$1};1')
            while IFS= read -r sourceLine; do
                if [[ ! -z "$sourceLine" && "$sourceLine" == *'('* ]]; then
                    sourceKey=$(echo "$sourceLine" | cut -d '(' -f 1 | awk '{$1=$1};1')
                    if [[ "$sourceKey" == "$key"* ]]; then
                    # Replace the target line with the source line
                    targetLine="   $sourceLine"
                    break  # No need to check the remaining lines in the source file
                    fi
                fi
            done < $sourceFilePath
        echo "$targetLine" >> "$tempFile"    
        else 
            echo "$targetLine" >> "$tempFile"  
        fi
    done < $mkFileName
    mv "$tempFile" "$mkFileName"
}

callSplitter(){
    mkFileName="${WORKSPACE}/aqa-tests/jck/subdirs/jck${JDK_VERSION}.mk"

    if [[ "$JDK_VERSION" == "8" ]]; then
        JDK_VERSION="8d"
    elif [[ "$JDK_VERSION" == "11" ]]; then
        JDK_VERSION="11a"
    fi

    TARGET_TO_SPLIT="${WORKSPACE}/test/JCK-compiler-${JDK_VERSION}/tests/lang"
    
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
            ${SCRIPT} > ${logFileName}
            #return_status=$?
            lastLine=$(grep -E "COMPILER_LANG_${key}_TESTS_GROUP|VERIFIER_INSTRUCTIONS_TESTS_GROUP" "$logFileName" | tail -n 1)
            # Check if the last line is present in the target file
            if grep -qF "$lastLine" "$mkFileName"; then
            echo "No need to create PR for --- $key"
            else
            #echo "We need to create PR for --- $key"
            testClassList+=("$key")
            updateJCKmkFile $logFileName
            PR_NEEDED=true
            fi
        fi
    done
    # for value in "${testClassList[@]}"; do
    #     echo $value
    # done
    echo "PR_NEEDED=$PR_NEEDED"
    echo -e "Splitter.sh resulted in new test groups. We need to create PR to update jck.mk file for below test group \n ${testClassList[@]}"
}


WORKSPACE=$1
JDK_VERSION=$2

keys=("ANNOT" "CLSS" "CONV" "DASG" "EXPR" "INTF" "LMBD" "NAME" "TYPE" "STMT" "VERIFIER")
values=("5" "10" "5" "5" "11" "5" "5" "5" "5" "5" "4")
PR_NEEDED=false
testClassList=()
callSplitter
