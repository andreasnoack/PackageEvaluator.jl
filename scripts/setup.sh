#!/usr/bin/env bash
#######################################################################
# PackageEvaluator
# https://github.com/JuliaCI/PackageEvaluator.jl
# (c) Iain Dunning and contributors 2015
# Licensed under the MIT License
#######################################################################
# This script file is the provisioning script run by Vagrant after
# the VM is created. It sets up the environment for running PkgEval,
# then runs it to produce the JSON result files.
#
# Commandline arguments for this script, passed through by Vagrant.
# 1st: Julia version:   0.5 | 0.6 | 0.7
# 2nd: Test set to run: setup | all | AK | LZ
#######################################################################


#######################################################################
# Accept all apt-gets
# This is an attempt to deal with BinDeps packages trying to install
# dependencies with apt-get and asking for permissions. Normally we
# could pass a --yes argument to avoid this, but there isn't a way to
# do that with BinDeps. We can actually do a global override, which
# is what we do here. Since we are piping stuff into a file, the
# easiest way to sudo the whole thing is to do it in this style.
sudo su -c 'echo "APT::Get::Assume-Yes \"true\";" > /etc/apt/apt.conf.d/pkgevalforceyes'
sudo su -c 'echo "APT::Get::force-yes \"true\";" >> /etc/apt/apt.conf.d/pkgevalforceyes'
# Don't install "recommends" junk
sudo su -c 'echo "APT::Install-Recommends \"false\";" >> /etc/apt/apt.conf.d/pkgevalforceyes'
# Uncomment following line to check it did indeed work
#cat /etc/apt/apt.conf.d/pkgevalforceyes


#######################################################################
# Use newest R release
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E084DAB9
sudo add-apt-repository -y "deb http://cran.rstudio.com/bin/linux/ubuntu trusty/"

# Newer cmake ppa
sudo add-apt-repository -y ppa:adrozdoff/cmake

# Set a 10 minute absolute timeout and 2 minute low speed timeout
# for curl because of unreliable downloads like wcslib, graphviz
echo "max-time = 600" >> ~/.curlrc
echo "speed-time = 120" >> ~/.curlrc
# Make wget non-verbose because progress bars mess with text file logging
echo "verbose = off" >> ~/.wgetrc

# Upgrade the installation and install Julia
sudo apt-get update    # Pull in latest versions
sudo apt-get upgrade   # Upgrade system packages
# Use first argument to script to distinguish between the versions
if [ "$1" == "0.7" ]
then
    # Nightly
    wget -O julia.tar.gz https://julialangnightlies-s3.julialang.org/bin/linux/x64/julia-latest-linux64.tar.gz
else
    wget -O julia.tar.gz https://julialang-s3.julialang.org/bin/linux/x64/${1}/julia-${1}-latest-linux-x86_64.tar.gz
fi
mkdir julia
tar -zxf julia.tar.gz -C ./julia --strip-components=1
rm julia.tar.gz
export PATH="${PATH}:/home/vagrant/julia/bin/"
# Retain PATH to make it easier to use VM for debugging
echo "export PATH=\"\${PATH}:/home/vagrant/julia/bin/\"" >> /home/vagrant/.profile

#######################################################################
# Install any dependencies that aren't handled by BinDeps
# Somethings can't be or don't make sense to be installed by BinDeps,
# so we will do them manually. Package maintainers can submit PRs to
# extend this list as needed.
# Need git of course, doesn't come by default in the image
sudo apt-get install git
# Need X virtual frame buffer for many packages
sudo apt-get install xvfb
# Need GMP for e.g. GLPK, why not get some PCRE too
sudo apt-get install libpcre3-dev libgmp-dev
# Need gfortran for e.g. GLMNet.jl, Ipopt.jl, KernSmooth.jl...
sudo apt-get install gfortran pkg-config
# Need unzip for e.g. Blink.jl, FLANN.jl
sudo apt-get install unzip
# Need cmake for e.g. GLFW.jl, Metis.jl
sudo apt-get install cmake
# Install R for e.g. Rif.jl, RCall.jl
sudo apt-get install r-base r-base-dev
# R packages for BioBridgeR.jl
sudo Rscript -e 'install.packages("ape", repos = "http://cran.rstudio.com/")'
# Install gmsh and libav-tools for EllipticFEM.jl
sudo apt-get install gmsh libav-tools
# Install Java for e.g. JavaCall.jl, Taro.jl
sudo add-apt-repository -y ppa:openjdk-r/ppa
sudo apt-get update
sudo apt-get install openjdk-8-jdk
export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
echo "export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64" >> /home/vagrant/.profile
# Use the Conda Package as Python environment
export PYTHON=""
# Need /usr/share/dict/words for TextAnalysis.jl
sudo apt-get install wamerican
# Need xmllint (and others?) for XMLDict.jl
sudo apt-get install libxml2-utils
# Need lualatex for TikzGraphs.jl (this is a big download and takes a long time)
#sudo apt-get install texlive-latex-base texlive-latex-extra \
#    texlive-luatex texlive-xetex pgf lmodern
# Install ubuntu's netcdf since conda likes breaking theirs
sudo apt-get install libnetcdf-dev
# Need gnuplot for Gaston.jl
sudo apt-get install gnuplot
# ArrayFire
AFSCRIPT=ArrayFire-no-gl-v3.4.2_Linux_x86_64.sh
wget http://ci.arrayfire.org/userContent/Linux/$AFSCRIPT
sudo chmod +x $AFSCRIPT
sudo ./$AFSCRIPT --exclude-subdir --prefix=/usr/local
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib/
rm $AFSCRIPT


#######################################################################
# Get PackageEvaluator scripts
PKGEVALDIR="/home/vagrant/pkgeval"
git clone https://github.com/JuliaCI/PackageEvaluator.jl.git $PKGEVALDIR
# Make results folders. Folder name is second argument to this script.
# These folders are shared - i.e. we are writing to outside the VM,
# most likely the PackageEvaluator.jl/scripts folder.
rm -rf /vagrant/${1}${2}
mkdir /vagrant/${1}${2}
cd /vagrant/${1}${2}
# Initialize METADATA for testing
# Note that it is important for it to not be in the /vagrant/ folder as
# that seems to mess with symlinks quite badly.
# See https://github.com/JuliaOpt/Ipopt.jl/issues/31 for discussion
# about this breaking a build.
julia -e "Pkg.init(); println(Pkg.dir())"


#######################################################################
# Run PackageEvaluator
if [ "$2" == "all" ]
then
    LOOPOVER=/home/vagrant/.julia/v${1}/METADATA/*
elif [ "$2" == "AK" ]
then
    LOOPOVER=/home/vagrant/.julia/v${1}/METADATA/[A-K,a-k]*;
elif [ "$2" == "LZ" ]
then
    LOOPOVER=/home/vagrant/.julia/v${1}/METADATA/[L-Z,l-z]*;
fi
# For every package name...
for f in $LOOPOVER;
do
    # Extract just the package name from the path
    PKGNAME=$(basename "$f")
    # Attempt to add the package. We give it half an hour - most
    # use far less, some do push it. CoinOptServices.jl set the
    # standard for build time and memory consumption, see
    # https://github.com/JuliaCI/PackageEvaluator.jl/issues/83
    # The log for adding the package will go in the results folder.
    timeout -s 9 1800s julia -e "Pkg.add(\"${PKGNAME}\")" 2>&1 | tee PKGEVAL_${PKGNAME}_add.log
    # A package can have four states:
    # - Not testable: for some reason, we can't even analyze how
    #   broken or not the package is, usually due to a limitation
    #   of PackageEvaluaor itself.
    # - No tests: the package doesn't even have tests. We used to
    #   further distinguish this by seeing if the package loads,
    #   but loading doesn't mean it actually works so this is bit
    #   misleading.
    # - Tests fail: the package has tests, and they don't pass.
    # - Tests pass: the tests pass!
    # We first run a script that:
    # - Identifies if we are testable or not. If we are not,
    #   exit with status 1 (not testable), or 2 (no tests).
    # - If we are, create a shell script to run the tests that
    #   includes xvfb, timeout, etc.
    julia $PKGEVALDIR/src/preptest.jl $PKGNAME
    TESTSTATUS=$?
    if [ $TESTSTATUS -eq 255 ]
    then
        # Not testable
        echo "NOT TESTABLE"
    elif [ $TESTSTATUS -eq 254 ]
    then
        # No tests
        echo "NO TESTS"
    else
        # Has tests, we need to run them
        # preptest.jl should have created a shell script to
        # run them. We just need to run that shell script
        # and store the error code. A code of 0 means the
        # tests passed, a code of 1 means Julia threw an
        # error, and a code of 124 means timeout triggered
        chmod +x $PKGNAME.sh
        ./$PKGNAME.sh
        TESTSTATUS=$?
    fi
    # We now want to bundle up the adding and testing results,
    # as well as other useful information about the package,
    # into a JSON that we can concatenate with the rest of the
    # results later on.
    # TODO: Avoid the need to add JSON each time,
    # even if it is just a simple move effectively. Can we
    # just pull the encoding part out of JSON, which is all
    # we really need because most of it is parsing?
    julia -e 'Pkg.add("JSON")'
    julia $PKGEVALDIR/src/prepjson.jl $PKGNAME $TESTSTATUS /vagrant/${1}${2}
    # Finish up by removing the package. Doesn't actually remove
    # it in the sense of deleting the files - this helps the
    # overall process run faster, if my understanding of how
    # the .trash folder works is correct.
    # Called twice in case the package makes itself dirty
    julia -e "Pkg.rm(\"${PKGNAME}\"); Pkg.rm(\"${PKGNAME}\")"
    # In case something confusing happens?
    julia -e "Pkg.status()"
done


#######################################################################
# Bundle results together
echo "Bundling results"
cd /vagrant/
julia $PKGEVALDIR/src/joinjson.jl /vagrant/${1}${2} ${1}${2}


#######################################################################
echo "Finished normally! $1 $2"
