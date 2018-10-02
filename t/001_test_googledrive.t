#
#===============================================================================
#
#         FILE: 002_test_googledrive.t
#
#  DESCRIPTION: 
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: YOUR NAME (), 
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 28.09.2018 23:14:47
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use utf8;
use lib 'lib';
use File::Basename;
use File::Spec;
use Data::Printer;
use Net::Google::Drive;

use Test::More 'no_plan';

BEGIN {
    use_ok("Net::Google::Drive");
}

my $CLIENT_ID       = $ENV{GOOGLE_CLIENT_ID}        // '593952972427-e6dr18ua0leurrjtu9gl1766t1je1num.apps.googleusercontent.com';
my $CLIENT_SECRET   = $ENV{GOOGLE_CLIENT_SECRET}    // 'pK99-WlEd7kr7YcWIAVFOQpu';
my $ACCESS_TOKEN    = $ENV{GOOGLE_ACCESS_TOKEN}     // 'ya29.GlspBipu9sdZKYmO4t90eDiEUVIQ2mhIVuPWothJa2Xwihow_ka889DFPWt3GSSrSpvh3mWjKUCDn-QlRxZRxBuCuaRDFZ5Q9w2w5SHFYOn6f_F2JASA34xgbakr';
my $REFRESH_TOKEN   = $ENV{GOOGLE_REFRESH_TOKEN}    // '1/uKe_YszQbrwA6tHI5Att-VOYuktWt5iV9Q5fy-DrEjE';

my $drive = Net::Google::Drive->new(
                                        -client_id      => $CLIENT_ID,
                                        -client_secret  => $CLIENT_SECRET,
                                        -access_token   => $ACCESS_TOKEN,
                                        -refresh_token  => $REFRESH_TOKEN,
                                    );
isa_ok($drive, 'Net::Google::Drive');


####### TESTS ######
testSearchFileByName($drive);
testSearchFileByNameContains($drive);


sub testSearchFileByName{
    my ($drive) = @_;
    my $files = $drive->searchFileByName(
                            -filename   => 'drive_file.t',
                        );
    is (scalar(@$files), 1, "Test searchFileByName");
}

sub testSearchFileByNameContains {
    my ($drive) = @_;
    my $files = $drive->searchFileByNameContains(
                                -filename   => 'Тестовый',
                            );
    map {p $files} @$files;
    is (scalar(@$files), 1, "Test searchFileByNameContains");
}



