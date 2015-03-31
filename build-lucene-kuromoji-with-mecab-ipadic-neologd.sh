#!/bin/bash

########## Init  ##########
WORK_DIR=`pwd`

########## Proxy Settings ##########
#export http_proxy=http://your.proxy-host:your.proxy-port
#export https_proxy=http://your.proxy-host:your.proxy-port
#export ANT_OPTS='-DproxyHost=your.proxy-host -DproxyPort=your.proxy-port'

########## Variables ##########
## MeCab
MECAB_VERSION=mecab-0.996
MECAB_INSTALL_DIR=${WORK_DIR}/mecab

## MeCab IPA Dictionary
MECAB_IPA_DICTIONARY_VERSION=mecab-ipadic-2.7.0-20070801
DEFAULT_CHARSET=utf-8

## mecab-ipadic-NEologd
MAX_BASEFORM_LENGTH=15

## mecab-ipadic-NEologd Target Tag
MECAB_IPADIC_NEOLOGD_TAG=master

## Lucene Target Tag
LUCENE_VERSION_TAG=lucene_solr_5_0_0

## Source Package
DEFAULT_KUROMOJI_PACKAGE=org.apache.lucene.analysis.ja
REDEFINED_KUROMOJI_PACKAGE=${DEFAULT_KUROMOJI_PACKAGE}

########## Main Process ##########
if [ ! `which mecab` ]; then
    if [ ! -e ${MECAB_INSTALL_DIR}/bin/mecab ]; then
        echo '##### MeCab Install Local #####'

        if [ ! -e ${MECAB_VERSION}.tar.gz ]; then
            wget https://mecab.googlecode.com/files/${MECAB_VERSION}.tar.gz
        fi
        tar -zxf ${MECAB_VERSION}.tar.gz
        cd ${MECAB_VERSION}

        if [ ! -e ${MECAB_INSTALL_DIR} ]; then
            mkdir -p ${MECAB_INSTALL_DIR}
        fi

        ./configure --prefix=${MECAB_INSTALL_DIR}
        make
        make install

        PATH=${MECAB_INSTALL_DIR}/bin:${PATH}

        cd ${WORK_DIR}

        echo '##### MeCab IPA Dictionary Install Local #####'
        if [ ! -e ${MECAB_IPA_DICTIONARY_VERSION}.tar.gz ]; then
            wget https://mecab.googlecode.com/files/${MECAB_IPA_DICTIONARY_VERSION}.tar.gz
        fi
        tar -zxf ${MECAB_IPA_DICTIONARY_VERSION}.tar.gz
        cd ${MECAB_IPA_DICTIONARY_VERSION}
        ./configure --with-charset=${DEFAULT_CHARSET}
        make
        make install
    else
        PATH=${MECAB_INSTALL_DIR}/bin:${PATH}
    fi
fi

cd ${WORK_DIR}

echo '##### Download mecab-ipadic-NEologd #####'
if [ ! -e mecab-ipadic-neologd ]; then
    git clone https://github.com/neologd/mecab-ipadic-neologd.git
else
    cd mecab-ipadic-neologd

    if [ -d build ]; then
        rm -rf build
    fi

    git checkout *
    git checkout master
    git pull
    cd ..
fi

cd mecab-ipadic-neologd

git checkout ${MECAB_IPADIC_NEOLOGD_TAG}

libexec/make-mecab-ipadic-neologd.sh -L ${MAX_BASEFORM_LENGTH}

DIR=`pwd`

NEOLOGD_BUILD_DIR=`find ${DIR}/build/mecab-ipadic-* -maxdepth 1 -type d`
NEOLOGD_DIRNAME=`basename ${NEOLOGD_BUILD_DIR}`
NEOLOGD_VERSION_DATE=`echo ${NEOLOGD_DIRNAME} | perl -wp -e 's!.+-(\d+)!$1!'`

cd ${WORK_DIR}

echo '##### Lucene Repository Clone #####'
if [ ! -e lucene-solr ]; then
    git clone https://github.com/apache/lucene-solr.git
else
    cd lucene-solr
    git checkout *
    git checkout trunk
    ant clean
    git pull
    cd ..
fi

cd lucene-solr
LUCENE_SRC_DIR=`pwd`

git checkout ${LUCENE_VERSION_TAG}

cd lucene
ant ivy-bootstrap

cd analysis/kuromoji
KUROMOJI_SRC_DIR=`pwd`

git checkout build.xml

echo '##### Build Lucene Kuromoji, with mecab-ipadic-NEologd #####'
mkdir -p ${LUCENE_SRC_DIR}/lucene/build/analysis/kuromoji
cp -Rp ${NEOLOGD_BUILD_DIR} ${LUCENE_SRC_DIR}/lucene/build/analysis/kuromoji

if [ "${LUCENE_VERSION_TAG}" = "lucene_solr_5_0_0" ]; then
    echo '##### avoid https://issues.apache.org/jira/browse/LUCENE-6368 #####'
    perl -wp -i -e 's!^    try \(OutputStream os = Files.newOutputStream\(path\)\) {!    try (OutputStream os = new BufferedOutputStream(Files.newOutputStream(path))) {!' ${LUCENE_SRC_DIR}/lucene/core/src/java/org/apache/lucene/util/fst/FST.java
    perl -wp -i -e 's!^      save\(new OutputStreamDataOutput\(new BufferedOutputStream\(os\)\)\);!      save(new OutputStreamDataOutput(os));!' ${LUCENE_SRC_DIR}/lucene/core/src/java/org/apache/lucene/util/fst/FST.java
fi

perl -wp -i -e "s!^version.suffix=(.+)!version.suffix=${NEOLOGD_VERSION_DATE}-SNAPSHOT!" ${LUCENE_SRC_DIR}/lucene/version.properties
perl -wp -i -e 's!<project name="analyzers-kuromoji"!<project name="analyzers-kuromoji-ipadic-neologd"!' build.xml
perl -wp -i -e 's!maxmemory="[^"]+"!maxmemory="2g"!' build.xml

if [ "${REDEFINED_KUROMOJI_PACKAGE}" != "${DEFAULT_KUROMOJI_PACKAGE}" ]; then
    echo "##### redefine package [${DEFAULT_KUROMOJI_PACKAGE}] => [${REDEFINED_KUROMOJI_PACKAGE}] #####"

    ORIGINAL_SRC_DIR=`echo ${DEFAULT_KUROMOJI_PACKAGE} | perl -wp -e 's!\.!/!g'`
    NEW_SRC_DIR=`echo ${REDEFINED_KUROMOJI_PACKAGE} | perl -wp -e 's!\.!/!g'`

    test -d ${KUROMOJI_SRC_DIR}/src/java/${NEW_SRC_DIR} && rm -rf ${KUROMOJI_SRC_DIR}/src/java/${NEW_SRC_DIR}
    mkdir -p ${KUROMOJI_SRC_DIR}/src/java/${NEW_SRC_DIR}
    find ${KUROMOJI_SRC_DIR}/src/java/${ORIGINAL_SRC_DIR} -mindepth 1 -maxdepth 1 | xargs -I{} mv {} ${KUROMOJI_SRC_DIR}/src/java/${NEW_SRC_DIR}
    find ${KUROMOJI_SRC_DIR}/src/java/${NEW_SRC_DIR} -type f | xargs perl -wp -i -e "s!${DEFAULT_KUROMOJI_PACKAGE}!${REDEFINED_KUROMOJI_PACKAGE}!g"

    test -d ${KUROMOJI_SRC_DIR}/src/resources/${NEW_SRC_DIR} && rm -rf ${KUROMOJI_SRC_DIR}/src/resources/${NEW_SRC_DIR}
    mkdir -p ${KUROMOJI_SRC_DIR}/src/resources/${NEW_SRC_DIR}
    find ${KUROMOJI_SRC_DIR}/src/resources/${ORIGINAL_SRC_DIR} -mindepth 1 -maxdepth 1 | xargs -I{} mv {} ${KUROMOJI_SRC_DIR}/src/resources/${NEW_SRC_DIR}

    test -d ${KUROMOJI_SRC_DIR}/src/tools/java/${NEW_SRC_DIR} && rm -rf ${KUROMOJI_SRC_DIR}/src/tools/java/${NEW_SRC_DIR}
    mkdir -p ${KUROMOJI_SRC_DIR}/src/tools/java/${NEW_SRC_DIR}
    find ${KUROMOJI_SRC_DIR}/src/tools/java/${ORIGINAL_SRC_DIR} -mindepth 1 -maxdepth 1 | xargs -I{} mv {} ${KUROMOJI_SRC_DIR}/src/tools/java/${NEW_SRC_DIR}
    find ${KUROMOJI_SRC_DIR}/src/tools/java/${NEW_SRC_DIR} -type f | xargs perl -wp -i -e "s!${DEFAULT_KUROMOJI_PACKAGE}!${REDEFINED_KUROMOJI_PACKAGE}!g"

    perl -wp -i -e "s!${ORIGINAL_SRC_DIR}!${NEW_SRC_DIR}!g" build.xml
    perl -wp -i -e "s!${DEFAULT_KUROMOJI_PACKAGE}!${REDEFINED_KUROMOJI_PACKAGE}!g" build.xml
fi

ant -Dipadic.version=${NEOLOGD_DIRNAME} -Ddict.encoding=utf-8 regenerate
if [ $? -ne 0 ]; then
    echo 'Dictionary Build Fail.'
    exit 1
fi

ant jar-core
if [ $? -ne 0 ]; then
    echo 'Kuromoji Build Fail.'
    exit 1
fi

cd ${WORK_DIR}

cp ${LUCENE_SRC_DIR}/lucene/build/analysis/kuromoji/lucene-analyzers-kuromoji* ./.

ls -l lucene-analyzers-kuromoji*
echo '##### END #####'
