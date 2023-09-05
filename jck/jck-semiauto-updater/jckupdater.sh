#!/usr/bin/env bash

#set -eo pipefail


WORKSPACE="$(pwd)"/workspace
GIT_REPO="$(pwd)"/pr
JCK_VERSION=""
JCK_UPDATE_NUMBER=""
DOWNLOAD_URL=""
ARTIFACTORY_TOKEN=""
GIT_REPO_NAME=""
GIT_USER=""
GIT_DEV_BRANCH="autoBranch"
GIT_TOKEN=""
JCK_FOLDER_SUFFIX=""
JAVA_SDK_URL=""

usage ()
{
	echo 'Usage : jckupdater.sh  [--jck_version|-j ] : indicate JCK version to update.'
	echo '                [--artifactory_token|-at] : Token to access JCK artifactory: https://eu.artifactory.swg-devops.com/artifactory/jim-jck-generic-local.'
	echo '                [--git_username|-u] : Indicate GIT username.'
	echo '                [--git_token|-gt] : Git API Token to create PR.'
	echo '                [--git_dev_branch|-gb ] :  Optional. GIT_DEV_BRANCH name to clone repo. Default is main'
	echo '                [--java_home|-java] : optional. JAVA_HOME path. '
	echo '                [--java_sdk_url|-sdk_url] : optional. JAVA_SDK_URL to download JDK. Default is JDK17'


}


parseCommandLineArgs()
{
	while [ $# -gt 0 ] && [[ ."$1" = .-* ]] ; do
		opt="$1";
		shift;
		case "$opt" in
			"--jck_version" | "-j" )
				JCK_VERSION="$1"; shift;;

			"--git_username" | "-u")
				GIT_USER="$1"; shift;;

			"--artifactory_token" | "-at")
				ARTIFACTORY_TOKEN="$1"; shift;;

			"--java_home" | "-java" )
			 	JAVA_HOME="$1"; shift;;

			"--git_token" | "-gt" )
			 	GIT_TOKEN="$1"; shift;;

			"--git_dev_branch" | "-gb")
				GIT_DEV_BRANCH="$1"; shift;;

			"--java_sdk_url" | "-sdk_url")
				JAVA_SDK_URL="$1"; shift;;

			"--help" | "-h" )
				usage; exit 0;;

			*) echo >&2 "Invalid option: ${opt}"; echo "This option was unrecognized."; usage; exit 1;
		esac
	done
}

##Initial setup and print values provided
setup(){

	echo ""
	echo "JAVA_HOME=$JAVA_HOME"
	echo "WORKSPACE=$WORKSPACE"
	echo "GIT_REPO=$GIT_REPO"
	echo "JCK_VERSION=$JCK_VERSION"
	echo "GIT_DEV_BRANCH=$GIT_DEV_BRANCH"
	echo "GIT_USER=$GIT_USER"

	# update GIT_REPO_NAME based on the provided JCK_VERSION
	GIT_REPO_NAME="JCK${JCK_VERSION}-unzipped.git"
	echo "GIT_REPO_NAME=$GIT_REPO_NAME"
	
	JCK=$JCK_VERSION
	JCK_FOLDER_SUFFIX=$JCK_VERSION
	## Only for JCK 8 and 11 
	if [[ $JCK_VERSION == "8" ]]; then 
		JCK=1.8d
		JCK_FOLDER_SUFFIX="$JCK_VERSION"d
	elif [[ $JCK_VERSION == "11" ]]; then
		JCK=11a
		JCK_FOLDER_SUFFIX="$JCK_VERSION"a
	fi
	echo "JCK_FOLDER_SUFFIX=" $JCK_FOLDER_SUFFIX
	DOWNLOAD_URL="https://eu.artifactory.swg-devops.com/artifactory/jim-jck-generic-local/${JCK}/tck/"
	echo "DOWNLOAD_URL=$DOWNLOAD_URL"
	echo ""

	mkdir $WORKSPACE
	mkdir $GIT_REPO
	mkdir $WORKSPACE/unpackjck
	mkdir $WORKSPACE/jckmaterial
}


executeCmdWithRetry()
{
	set +e
	count=0
	rt_code=-1
	# when the command is not found (code 127), do not retry
	while [ "$rt_code" != 0 ] && [ "$rt_code" != 127 ] && [ "$count" -le 5 ]
	do
		if [ "$count" -gt 0 ]; then
			sleep_time=3
			echo "error code: $rt_code. Sleep $sleep_time secs, then retry $count..."
			sleep $sleep_time

			echo "check for $1. If found, the file will be removed."
			if [ "$1" != "" ] && [ -f "$1" ]; then
				echo "remove $1 before retry..."
				rm $1
			fi
		fi
		echo "$2"
		eval "$2"
		rt_code=$?
		count=$(( $count + 1 ))
	done
	set -e
	return "$rt_code"	
}



list() {
	file_list=$(curl -ks -H X-JFrog-Art-Api:${ARTIFACTORY_TOKEN} "${DOWNLOAD_URL}")

	# Use grep to filter out the content within <a href=""> tags
	file_names=$(echo "$file_list" | grep -o '<a href="[^"]*">' | sed 's/<a href="//;s/">//')	
}

isLatestUpdate() {
	cd $WORKSPACE/jckmaterial
	
	list # get the JCK update number from artifactory
	last_file=""
		for file in $file_names; do
    		last_file="$file"
		done
	
	JCK_UPDATE_NUMBER=$last_file

	JCK_WITHOUT_BACKSLASH="${JCK_UPDATE_NUMBER%/*}"
	#remove any "ga" associated with JCK_BUILD_ID
	JCK_WITHOUT_BACKSLASH=$(echo "$JCK_WITHOUT_BACKSLASH" | sed 's/-ga//g')
	echo "JCK_BUILD_ID - $JCK_WITHOUT_BACKSLASH"
	GIT_URL="https://raw.github.ibm.com/runtimes/JCK$JCK_VERSION-unzipped/main/JCK-compiler-$JCK_FOLDER_SUFFIX/build.txt"

	curl -o "build.txt" $GIT_URL -H "Authorization: token $GIT_TOKEN"
	echo -e "JCK version in build.txt:\n$(cat build.txt)\n\n"
	
	if grep -q "$JCK_WITHOUT_BACKSLASH" build.txt; then
		echo " JCK$JCK_VERSION material is $JCK_WITHOUT_BACKSLASH in the repo $GIT_URL. It is up to date. No need to pull changes"
		#clean up after testing
		#get_JAVA_SDK
		getJCKSources
		# cleanup
		# exit -1
	else	
		echo " JCK$JCK_VERSION $JCK_WITHOUT_BACKSLASH is latest and not in the repo $GIT_URL... Please proceed with download"
		get_JAVA_SDK
		getJCKSources
	fi
}

## Download directly from given URL under current folder
getJCKSources() {
	echo "remove build.txt file after comparison"
	rm -rf build.txt
	echo "download jck materials..."
	
	DOWNLOAD_URL=$DOWNLOAD_URL$JCK_UPDATE_NUMBER
	echo $DOWNLOAD_URL

	list #get list of files to download
	
	IFS=$'\n' read -r -d '' -a file_names_array <<< "$file_names"

	if [ "${DOWNLOAD_URL}" != "" ]; then
		for file in "${file_names_array[@]:1}"; do
			url="$DOWNLOAD_URL$file"
			executeCmdWithRetry "${file##*/}" "_ENCODE_FILE_NEW=UNTAGGED curl -OLJSk -H X-JFrog-Art-Api:${ARTIFACTORY_TOKEN} $url"

			rt_code=$?
			if [ $rt_code != 0 ]; then
				echo "curl error code: $rt_code"
				echo "Failed to retrieve $file. This is what we received of the file and MD5 sum:"
				ls -ld $file

				exit 1
			fi
		done	
	fi
}

#install Java
get_JAVA_SDK(){

		cd $WORKSPACE/../../../../openjdkbinary/j2sdk-image
		JAVA_SDK_PATH="$(pwd)"
		echo $JAVA_SDK_PATH
		$JAVA_SDK_PATH/bin/java -version
}

#Unpack downloaded jar files 
extract() {
	cd $WORKSPACE/jckmaterial
	
  	echo "install downloaded resources"

	for f in $WORKSPACE/jckmaterial/*.jar; do
		echo "Unpacking $f:"
		
		#using default java on machine for local
		if [[ $JAVA_HOME = "" ]] ; then
			#$JAVA_HOME/bin/java -jar $f -install shell_scripts -o $WORKSPACE/unpackjck
			java -version
			java -jar $f -install shell_scripts -o $WORKSPACE/unpackjck
		else
			$JAVA_SDK_PATH/bin/java -jar $f -install shell_scripts -o $WORKSPACE/unpackjck
		fi

	done
	cd $WORKSPACE/unpackjck
	ls -la
	echo "completed unpack of jck resources"
}

#Clone GIT branch.
gitClone()
{
	echo "Checking out git@github.ibm.com:$GIT_USER/$GIT_REPO_NAME and reset to git@github.ibm.com:runtimes/$GIT_REPO_NAME main branch in dir $GIT_REPO"
	cd $GIT_REPO
	git init
	git remote add origin git@github.ibm.com:$GIT_USER/"$GIT_REPO_NAME"
	git remote add upstream git@github.ibm.com:$GIT_USER/"$GIT_REPO_NAME" #change to runtimes after testing
	git remote -v
	git checkout -b $GIT_DEV_BRANCH
	git fetch upstream main
	git reset --hard upstream/main
	git branch -v
}

#Move unpacked files to GIT repository
copyFilestoGITRepo() {

	cd $GIT_REPO
	rm -rf JCK-compiler-$JCK_FOLDER_SUFFIX
	rm -rf JCK-runtime-$JCK_FOLDER_SUFFIX
	rm -rf JCK-devtools-$JCK_FOLDER_SUFFIX
	rm -rf headers
	rm -rf natives
	echo "copy unpacked JCK files from $WORKSPACE/unpackjck to local GIT dir $GIT_REPO"

	cd $WORKSPACE/unpackjck
	for file in $WORKSPACE/unpackjck/*; do
		echo $file
		cp -rf $file $GIT_REPO
	done

	#copy remaining file like .jtx, .kfl .html to GIT Repo
	for file in $WORKSPACE/jckmaterial/*; do
		if [[ "$file" != *.zip ]] && [[ "$file" != *.gz* ]] && [[ "$file" != *.jar ]];then
			if [[ "$file" == *.kfl* ]]  || [[ "$file" == *.jtx* ]]; then
				echo "Copy $file to $GIT_REPO"
				cp -rf $file $GIT_REPO/excludes
			else
	 			cp -rf $file $GIT_REPO
			fi
		fi
	done
	find $GIT_REPO -name .DS_Store -exec rm -rf {} \;
}


#Commit changes to local repo and Push changes to GIT branch.
checkChangesAndCommit() {
	cd $GIT_REPO
	# Check if there are any changes in the working directory
	if git diff --quiet  &&  git status --untracked-files=all | grep -q "nothing to commit" ; then
	   	echo "No changes to commit."
	else
		git config --global user.email "$GIT_USER@in.ibm.com"
		git config --global user.name "$GIT_USER"
		git add -A .
		#Commit and push to origin
		echo "Pushing the changes to git branch: $GIT_DEV_BRANCH..."
		git commit -am "Initial commit for JCK$JCK_FOLDER_SUFFIX $JCK_WITHOUT_BACKSLASH update"
		git push origin $GIT_DEV_BRANCH
		echo "Changes committed successfully."
		#Call only if there are any changes to commit.
		createPR
	fi
}


#Create PR from GIT_DEV_BRANCH to main branch. PR will not be merged.
#Call only if there are any changes to commit.
createPR(){
	cd $GIT_REPO

	# Add the base repository as a remote

	## Create a PR from GIT_DEV_BRANCH to main branch.
	## Will not merge PR and wait for review.

	title="JCK$JCK_VERSION $JCK_WITHOUT_BACKSLASH udpate"
	body="This is a new pull request for the JCK$JCK_VERSION $JCK_WITHOUT_BACKSLASH udpate"
	echo " Creating PR from $GIT_DEV_BRANCH to main branch"
	url="https://api.github.ibm.com/repos/$GIT_USER/JCK$JCK_VERSION-unzipped/pulls"

	response=$(curl -X POST \
	-H "Authorization: token $GIT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"title\":\"$title\",\"body\":\"$body\",\"head\":\"$GIT_USER:$GIT_DEV_BRANCH\",\"base\":\"main\"}" \
        "$url")
	
	# Assuming $response contains the JSON response
	#pr=$(echo "$response" | grep -o '"number":[0-9]*' | awk -F':' '{print $2}' | tr -d '," ')
	pr_number=$(echo "$response" | grep -o '"number": *[0-9]*' | awk -F':' '{print $2}' | tr -d ' ,"')

	# $pr_number now contains the PR number
	echo "PR Number=$pr_number"

	echo "Add comment to PR "
	comment="Test comment from script"
	comment_url="https://github.ibm.com/api/v3/repos/$GIT_USER/JCK$JCK_VERSION-unzipped/issues/$pr_number/comments"
	echo "comment_url -- $comment_url"

	comment_response=$(curl -X POST \
        -H "Authorization: token $GIT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"body\":\"$comment\"}" \
       	$comment_url)

}

test() {

	echo "Inside jckupdater script"
	response='{
	"url": "https://github.ibm.com/api/v3/repos/kapil-powar/JCK8-unzipped/pulls/4",
	"number": 4,
	"id": 12262634
	}'
	echo "Response -- $response"
	pr_number=$(echo "$response" | grep -o '"number": *[0-9]*' | awk -F':' '{print $2}' | tr -d ' ,"')

	echo "PR -- $pr_number"
	file_path="$WORKSPACE/../../test/file.txt"
	mkdir -p "$(dirname "$file_path")"
	touch "$file_path"
	echo "file path -- $file_path"
	echo "$pr_number" > "$file_path"
	echo "file contents--"
	cat "$file_path"
	chmod 0777 $file_path
}

cleanup() {
	echo "Starting clean up dir $WORKSPACE and $GIT_REPO ........"
	rm -rf $WORKSPACE
	rm -rf $GIT_REPO
	echo "Clean up successfull"
}

date
echo "Starting autojckupdater script.."
begin_time="$(date -u +%s)"

parseCommandLineArgs "$@"

if [ "$JCK_VERSION" != "" ] && [ "$GIT_USER" != "" ] && [ "$ARTIFACTORY_TOKEN" != "" ] && [ "$GIT_TOKEN" != "" ]  ; then
	# cleanup
	# setup
	# isLatestUpdate
	# extract
	# gitClone
	# copyFilestoGITRepo
	# checkChangesAndCommit
	# cleanup
	test
else 
	echo "Please provide missing arguments"
	usage; exit 1
fi

end_time="$(date -u +%s)"
date 
elapsed="$(($end_time-$begin_time))"
echo "Complete JCK update process took ~ $elapsed seconds."
echo ""