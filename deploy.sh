#!/bin/sh

FULL_PATH=$1;
PROJECT="$(basename "$FULL_PATH")";
DIRNAME="$(dirname "$FULL_PATH")";
SITEDEPLOYDIR=$(pwd);
AWS_PROFILE='jds';
AWS_REGION='us-west-1';

validate () {
  echo 'VALIDATING';
  usage="USAGE:\n\t./deploy <dir/project_name>\n\tYou must specify a directory and project name.";

  # check for project path/name
  if [ -z $FULL_PATH ]; then echo $usage; exit 1; fi;
  if [ -z $DIRNAME ] || [[ $DIRNAME = '.' ]] ; then echo $usage; exit 1; fi;
  if [ -z $PROJECT ]; then echo $usage; exit 1; fi;
  if [[ ! -d $DIRNAME ]]; then echo "path $DIRNAME does not exist"; exit 1; fi;

  # repo
  STATUS_CODE=$(curl https://github.com/stinkyfingers/$PROJECT -I -s -w "%{http_code}" -o /dev/null);
  if [ $STATUS_CODE -ne 200 ]; then echo 'Repository does not exist'; exit 1; fi;

  echo 'building project at:' $FULL_PATH;
}

tf () {
  echo 'TERRAFORM';
  cd $FULL_PATH;
  echo 'here', $PWD
  echo "terraform/.terraform/*\nterraform/terraform.tfstate*" >> .gitignore;

  rm -rf $FULL_PATH/terraform; # TODO remove
  cp -r $SITEDEPLOYDIR/terraform terraform;

  echo "
  project=\"$PROJECT\"
  " > .tfvars;

  echo "terraform {
    backend \"s3\" {
      bucket = \"remotebackend\"
      key    = \"${PROJECT}/terraform.tfstate\"
      region = \"${AWS_REGION}\"
      profile = \"${AWS_PROFILE}\"
    }
  }" > terraform/backend.tf;

  cd terraform;
  terraform init;
  terraform apply -auto-approve -var="project=$PROJECT" -var="region=$AWS_REGION";
}

react_app () {
  echo 'REACTJS APP';
  cd $DIRNAME;
  npx create-react-app $PROJECT;
}

buildspec () {
  echo 'CI';

  cd $FULL_PATH;
  # get distribution id
  DISTRIBUTION_ID=$(aws cloudfront list-distributions --profile $AWS_PROFILE | jq -r ".DistributionList.Items[] | select(.DefaultCacheBehavior.TargetOriginId==\"$PROJECT-origin\") | .Id");
  echo "version: 0.2
phases:
  install:
    runtime-versions:
      nodejs: 10
  pre_build:
    commands:
      - yarn
  build:
    commands:
      - yarn build
  post_build:
    commands:
      - aws s3 sync build s3://$PROJECT.john-shenk.com
      - aws cloudfront create-invalidation --paths /index.html --distribution-id $DISTRIBUTION_ID
artifacts:
  files:
    - 'build/*'
" > buildspec.yml;
}

version_control () {
  echo 'VERSION CONTROL';
  cd $FULL_PATH;
  git init;
  git add -A;
  git commit -am "first commmit";
  git remote add origin https://github.com/stinkyfingers/$PROJECT.git;
  git push -u origin master;
}

validate;
react_app;
tf;
buildspec;
version_control;
