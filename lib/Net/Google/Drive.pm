package Net::Google::Drive;

use 5.008001;
use strict;
use warnings;
use utf8;

use lib '/home/vrag/perl/googleoauth/lib';

use LWP::UserAgent;
use HTTP::Request;
use JSON::XS;
use URI::Escape;
use URI;
use File::Basename;

use Carp qw/carp croak/;

use Net::Google::OAuth;

use Data::Printer;

our $VERSION = '0.01';

our $DOWNLOAD_BUFF_SIZE = 1024;
our $UPLOAD_BUFF_SIZE = 256 * 1024;

sub new {
    my ($class, %opt) = @_;

    my $self                    = {};
    my $client_id               = $opt{-client_id}          // croak "You must specify '-client_id' param";
    my $client_secret           = $opt{-client_secret}      // croak "You must specify '-client_secret' param";
    $self->{access_token}       = $opt{-access_token}       // croak "You must specify '-access_token' param";
    $self->{refresh_token}      = $opt{-refresh_token}      // croak "You must specify '-refresh_token' param";
    $self->{ua}                 = LWP::UserAgent->new();

    $self->{oauth}              = Net::Google::OAuth->new(
                                                -client_id      => $client_id,
                                                -client_secret  => $client_secret,
                                            );
    bless $self, $class;
    return $self;
}

sub searchFileByName {
    my ($self, %opt)        = @_;
    my $filename            = $opt{-filename}      || croak "You must specify '-filename' param";

    my $search_res = $self->__searchFile('name=\'' . $filename . "'");
 
    return $search_res;
}

sub searchFileByNameContains {
    my ($self, %opt)        = @_;
    my $filename            = $opt{-filename}      || croak "You must specify '-filename' param";

    my $search_res = $self->__searchFile('name contains \'' . $filename . "'");
 
    return $search_res;
}


sub downloadFile {
    my ($self, %opt)        = @_;
    my $file_id             = $opt{-file_id}        || croak "You must specify '-file_id' param";
    my $dest_file           = $opt{-dest_file}      || croak "You must specify '-dest_file' param";
    my $ua                  = $self->{ua};
    my $access_token        = $self->__getAccessToken();

    my $uri = URI->new('https://www.googleapis.com/drive/v3/files/' . $file_id);
    $uri->query_form(
                        'alt'               => 'media',
                    );
    my $headers = [
        'Authorization' => 'Bearer ' . $access_token,
    ];

    my $request = HTTP::Request->new(   'GET',
                                        $uri,
                                        $headers,
                            );

    my $FL;
    my $response = $ua->request($request, sub {
                                                    if (not $FL) {
                                                        open $FL, ">$dest_file" or croak "Cant open $dest_file to write $!";
                                                        binmode $FL;
                                                    }
                                                    print $FL $_[0];
                                                }, 
                                                $DOWNLOAD_BUFF_SIZE
                                            );
    close $FL if $FL;
    my $response_code = $response->code();
    if ($response_code != 200) {
        my $error_message = __readErrorMessageFromResponse($response);
        croak "Can't download file id: $file_id to destination file: $dest_file. Code: $response_code. Message: '$error_message'";
    }
    return 1;
}

sub deleteFile {
    my ($self, %opt)        = @_;
    my $file_id             = $opt{-file_id}        || croak "You must specify '-file_id' param";
    my $access_token        = $self->__getAccessToken();

    my $uri = URI->new('https://www.googleapis.com/drive/v3/files/' . $file_id);
    my $headers = [
        'Authorization' => 'Bearer ' . $access_token,
    ];

    my $request = HTTP::Request->new(   'DELETE',
                                        $uri,
                                        $headers,
                            );
    my $response = $self->{ua}->request($request);
    my $response_code = $response->code();
    if ($response_code != 200) {
        my $error_message = __readErrorMessageFromResponse($response);
        croak "Can't delete file id: $file_id. Code: $response_code. Message: $error_message";
    }
    return 1;
}

sub uploadFile {
    my ($self, %opt)                    = @_;
    my $source_file                     = $opt{-source_file}        || croak "You must specify '-source_file' param";

    croak "File: $source_file not exists" if not -f $source_file;

    my $file_size = (stat $source_file)[7];
    my $part_upload_uri = $self->__createEmptyFile($source_file, $file_size);
    open my $FH, "<$source_file" or croak "Can't open file: $source_file $!";
    binmode $FH;

    my $filebuf;
    my $uri = URI->new($part_upload_uri);
    my $start_byte = 0;
    while (my $bytes = read($FH, $filebuf, $UPLOAD_BUFF_SIZE)) {
        my $end_byte = $start_byte + $bytes - 1;
        my $headers = [
            'Content-Length'    => $bytes,
            'Content-Range'     => sprintf("bytes %d-%d/%d", $start_byte, $end_byte, $file_size),
        ];
        my $request = HTTP::Request->new('PUT', $uri, $headers, $filebuf);

        # Send request to upload part of file
        my $response = $self->{ua}->request($request);
        my $response_code = $response->code();
        # On end part, response code is 200, on middle part is 308
        if ($response_code == 200 || $response_code == 201) {
            if ($end_byte + 1 != $file_size) {
                croak "Server return code: $response_code on upload file, but file is not fully uploaded. End byte: $end_byte. File size: $file_size. File: $source_file";
            }
            return decode_json($response->content());
        }
        elsif ($response_code != 308) {
            croak "Wrong response code on upload part file. Code: $response_code. File: $source_file";
        }
        $start_byte += $bytes;
    }
    close $FH;

    return;
}

sub __createEmptyFile {
    my ($self, $source_file, $file_size)        = @_;
    my $access_token                            = $self->__getAccessToken();

    my $body = {
        'name'  => basename($source_file),
    };
    my $body_json = encode_json($body);

    my $uri = URI->new('https://www.googleapis.com/upload/drive/v3/files?upload_type=resumable');
    my $headers = [
        'Authorization'             => 'Bearer ' . $access_token,
        'Content-Length'            => length($body_json),
        'Content-Type'              => 'application/json; charset=UTF-8',
        'X-Upload-Content-Length'   => $file_size,
    ];

    my $request = HTTP::Request->new('POST', $uri, $headers, $body_json);
    my $response = $self->{ua}->request($request);

    my $response_code = $response->code();
    if ($response_code != 200) {
        my $error_message = __readErrorMessageFromResponse($response);
        croak "Can't upload part of file. Code: $response_code. Error message: $error_message";
    }

    my $location = $response->header('Location') or croak "Locatio header not defined";

    return $location;
}

sub __readErrorMessageFromResponse {
    my ($response) = @_;
    my $error_message = eval {decode_json($response->content)};
    if ($error_message) {
        return $error_message->{error}->{message};
    }
    return '';
}



sub __searchFile {
    my ($self, $q) = @_;

    $q = uri_escape_utf8($q);

    my $access_token = $self->__getAccessToken();
    
    my $headers = [
        'Authorization' => 'Bearer ' . $access_token,
    ];

    my $request = HTTP::Request->new('GET',
                                'https://www.googleapis.com/drive/v3/files?q=' . $q,
                                $headers,
                            );
    my $files = [];
    $self->__apiRequest($request, $files);


    return $files;
}

sub __apiRequest {
    my ($self, $request, $files) = @_;

    my $response = $self->{ua}->request($request);
    my $response_code = $response->code;
    croak "Wrong response code on search_file. Code: $response_code" if $response_code != 200;

    my $json_res = decode_json($response->content);

    if (my $next_token = $json_res->{next_token}) {
        my $uri = $request->uri;
        $uri->query_form('next_token' => $next_token);
        $self->__apiRequest($request, $files);
    }
    push @$files, @{$json_res->{files}};

    return 1;
}

sub __getAccessToken {
    my ($self) = @_;

    my $oauth = $self->{oauth};
    my $token_info = 
        eval {
            $oauth->getTokenInfo( -access_token => $self->{access_token} );
        };
    # If error on get token info or token is expired
    if (not $@) {
        if ((exists $token_info->{expires_in}) && ($token_info->{expires_in} > 5)) {
            return $self->{access_token};
        }
    }

    #Refresh token
    $oauth->refreshToken( -refresh_token => $self->{refresh_token} );
    $self->{refresh_token} = $oauth->getRefreshToken();
    $self->{access_token} = $oauth->getAccessToken();

    return $self->{access_token};
}



1;
