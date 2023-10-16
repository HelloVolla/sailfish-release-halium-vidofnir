#!/bin/bash
set -e
echo "Prepare steps..."
cd /share
sudo mkdir -p output
sudo mkdir -p build
sudo chmod 777 output
sudo chmod 777 build
cd build

echo "Install packages..."
sudo zypper -n in kmod lvm2 atruncate pigz android-tools  curl clang git zlib-devel glibc-devel glibc-static libstdc++-devel p7zip ;

# Creates an image under mic/fe-$DEVICE-$RELEASE$EXTRA_NAME 
# after downloading the kickstart file from the testing or devel repo.	

echo "Build Image..."
VERSION=devel
RELEASE=""

while :; do
    case $1 in
	--release)
	    RELEASE=$2
	    shift
	    ;;

	--version)
	    VERSION=$2
	    shift
	    ;;

	*)
	    break
    esac
    shift
done

[ -z "$VENDOR" ] && (echo "Vendor has to be specified with VENDOR= env" && exit -1)
[ -z "$DEVICE" ] && (echo "Device has to be specified with DEVICE= env" && exit -1)
[ -z "$RELEASE" ] && (echo "Release has to be specified with --release option" && exit -1)

case $VERSION in
    testing)
		URL=http://repo.merproject.org/obs/nemo:/testing:/hw:/$VENDOR:/$DEVICE/sailfishos_${RELEASE}
		;;
    devel)
		URL=http://repo.merproject.org/obs/nemo:/devel:/hw:/$VENDOR:/$DEVICE/sailfish_latest_$PORT_ARCH
		;;
    *)
	echo "Version (devel or testing) is not specified using --testing option"
    	exit -2
		;;
esac

TMPWORKDIR=/tmp/create-image
mkdir -p $TMPWORKDIR

OUTPUTDIR=$(pwd)/mic
mkdir -p $OUTPUTDIR

echo "Downloading from $URL/repodata/repomd.xml"
# Removing the xmlns from the xml as default namespace is almost unusable.
curl -L "$URL/repodata/repomd.xml" --output - | sed -e 's/xmlns=".*"//g' > $TMPWORKDIR/repomd.xml
PRIMARY=$(xmllint --xpath "string(/repomd/data[@type='primary']/location/@href)" $TMPWORKDIR/repomd.xml)

echo "Downloading from $URL/$PRIMARY"
curl -L "$URL/$PRIMARY" --output - | gunzip > $TMPWORKDIR/primary.xml
# Got away without referencing elements from default namespace, attributes work.
KICKSTART=$(xmllint --xpath "string(//*[contains(@href, 'droid-config-$DEVICE-ssu-kickstarts')]/@href)" $TMPWORKDIR/primary.xml)

echo "Downloading from $URL/$KICKSTART"
#rm -rf $TMPWORKDIR/rpm/
curl -L "$URL/$KICKSTART" --output - | rpm2cpio - | cpio -idmv -D $TMPWORKDIR/rpm/

# make gz not bz2
#sed -e "s/\.bz2/\.gz/g" $TMPWORKDIR/rpm/usr/share/kickstarts/Jolla-\@RELEASE\@-$DEVICE-\@ARCH\@.ks > $OUTPUTDIR/Jolla-\@RELEASE\@-$DEVICE-\@ARCH\@.ks
cp $TMPWORKDIR/rpm/usr/share/kickstarts/Jolla-\@RELEASE\@-$DEVICE-$VERSION-\@ARCH\@.ks $OUTPUTDIR/Jolla-\@RELEASE\@-$DEVICE-$VERSION-\@ARCH\@.ks

mount
df -h

echo "Creating mic with $OUTPUTDIR/Jolla-\@RELEASE\@-$DEVICE-$VERSION-\@ARCH\@.ks "
sudo mic create loop --arch=$PORT_ARCH \
 --tokenmap=ARCH:$PORT_ARCH,RELEASE:$RELEASE,EXTRA_NAME:$EXTRA_NAME,DEVICEMODEL:$DEVICE \
 --record-pkgs=name,url \
 --outdir=$OUTPUTDIR/sfe-$DEVICE-$RELEASE$EXTRA_NAME \
 $OUTPUTDIR/Jolla-\@RELEASE\@-$DEVICE-$VERSION-\@ARCH\@.ks 

# create fastboot flashable super.img
find
echo "Build tools for super.img creation..."

git clone https://github.com/LonelyFool/lpunpack_and_lpmake.git
cd lpunpack_and_lpmake
export LDFLAGS="-lstdc++fs -L/usr/lib/gcc/aarch64-meego-linux-gnuabi/8.3.0/"
./make.sh && cd ..
#curl -O https://volla.tech/filedump/ubuntu-touch-mimameid-firmware-r.tar.xz
#tar xvJf ubuntu-touch-mimameid-firmware-r.tar.xz

echo "Create super.img..."
./lpunpack_and_lpmake/bin/lpmake --metadata-size 65536 --metadata-slots 1 --sparse --super-name super --device super:8589934592 --group sailfish:8585740288 --partition system_a:none:8388608000:sailfish --image system_a=$OUTPUTDIR/sfe-$DEVICE-$RELEASE$EXTRA_NAME/root.img --output $OUTPUTDIR/sfe-$DEVICE-$RELEASE$EXTRA_NAME/super.img

echo "Pack final image..."
mv $OUTPUTDIR/sfe-$DEVICE-$RELEASE$EXTRA_NAME $OUTPUTDIR/SailfishOS-vidofnir
rm $OUTPUTDIR/SailfishOS-vidofnir/root.img
7z a -t7z -m0=lzma -mx=9 -mfb=64 -md=32m -ms=on $OUTPUTDIR/SailfishOS-vidofnir.7z  $OUTPUTDIR/SailfishOS-vidofnir
	    
