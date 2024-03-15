#
# Helper scrit for remembering the installation of the BrosTrend WiFi USB stick on Raspberry Pi 3
#

echo "#"
echo "# Executing the Installation script for the BrosTrend WiFi adapter..."
echo "# Please select option 'b' RealTek 88x2bu for the model (per lsusb output)!"
echo "#"

sh -c 'wget deb.trendtechcn.com/install -O /tmp/install && sh /tmp/install'
