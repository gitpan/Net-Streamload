package Net::Streamload;
# $Id: Streamload.pm,v 1.2 2004/02/27 18:03:31 tobias Exp $

=head1 NAME

Net::Streamload - Perl extension to upload files to streamload.com

=head1 SYNOPSIS

	use Net::Streamload;
	$sl = Net::Streamload->new(
			Username => $username,
			Password => $password,
			Server   => 'upload.streamload.com',
			Port     => '9914');
	$sl->login();
	$status = $sl->logged_in();
	$sl->ensure_folder($parent, $name, $use_if_exist);
	$sl->upload($parent, $file, $use_if_exist, \&status_sub);
	$sl->url_streamload($parent, $url, $use_if_exist, \&status_sub);
	$sl->logout();

=head1 DESCRIPTION

This is a module to upload files to streamload.com, a really cool storing
system for media files.

=cut

require 5.005_62;
use strict;
use warnings;
use Carp;

use Socket;
use Digest::MD5;

our $VERSION = '0.03';

# Debug messages?
my $DEBUG = 0;

# Version of the API
my $verMajor = 1;
my $verMinor = 2;

# Message types
my $cMsgLogin         = 0;
my $cMsgEnsureFolder  = 1;
my $cMsgUploadInit    = 2;
my $cMsgURLStreamload = 3;

=head1 METHODS

=over 4

=item $sl = Net::Streamload->new(...);

This creates a new Streamload-object. You can pass your Streamload username and
password (the password is B<not> needed at the moment, so don't specify any).
You can also change the Streamload server and port in this call. The server
defaults to C<upload.streamload.com> and the port to C<9914>. The last thing you
may specify is the B<buffer size> of the  of the upload stream. The standard
value is 10kB (10240 Byte). This may be too much on slow connections! A typical
call could look like this:

	$sl = Net::Streamload->new(
			Username   => 'MisterX',
			Server     => 'upload.streamload.com',
			Port       => 9914,
			Buffersize => 10240);

=cut

sub new
{
	my $class = shift;
	my $self = {
		connected  => 0,
		Server     => 'upload.streamload.com',
		Port       => 9914,
		Username   => '',
		Password   => '',
		Buffersize => 10240, # Buffersize for uploading files (10k)
		@_ };
	bless($self, $class);

	return $self;
}

=item $sl->login();

This connects to the Streamload server and sends the login command. You should
call this before performing any other action. It raises an exception if
something went wrong. You can query $@ then!

=cut

sub login
{
	my $self = shift;
	croak "No Streamload username supplied!" if $self->{Username} eq '';

	# Create socket
	socket(SERVER, PF_INET, SOCK_STREAM, getprotobyname('tcp'));

	# Get IP from hostname
	my $ip = inet_aton($self->{Server})
		or croak "Could not resolve hostname $self->{Server}: $!";
	my $peeraddr = sockaddr_in($self->{Port}, $ip);

	print "Connecting to $self->{Server}:$self->{Port}...\n" if $DEBUG;

	# Try to connect
	connect(SERVER, $peeraddr)
		or croak "Could not connect to $self->{Server}:$self->{Port}: $!";

	# Now that we have a connection, save the filehandle for further use.
	$self->{server} = *SERVER;

	print "Logging in...\n" if $DEBUG;

	# Login to Streamload
	my $command = pack("VVVVa*Va*", $cMsgLogin, $verMajor, $verMinor,
		length($self->{Username}), $self->{Username},
		length($self->{Password}), $self->{Password});
	$self->send_server($command, length($command));

	# Get response
	my $response = $self->receive_server(1);
	# Is the login OK?
	unpack("C", $response) || $self->_handle_error();

	# Read the folder IDs (4x 64-Bit signed integer)
	$response = $self->receive_server(32);
	#my @ids = unpack("q*", $response); # Not portable in any way!

	# Cut in 64-Bit (8-Byte) Chunks
	$self->{folders} = {
		"My Stuff"  => substr($response, 0 * 8, 8),
		# "My Stuff"  => substr($response, 1 * 8, 8), # Same as above
		"Playlists" => substr($response, 2 * 8, 8),
		"Inbox"     => substr($response, 3 * 8, 8)
	};

	$self->{connected} = 1;

	print "Logged in succesfullly.\n" if $DEBUG;
	1;
}

=item $status = $sl->logged_in();

This is to check if you are already logged in.

=cut

sub logged_in
{
	my $self = shift;
	$self->{connected};
}

=item $sl->ensure_folder($parent, $name, $use_if_exist);

You can use this function to check if a folder is there. The folder will be
created if it isn't there. The function takes three parameters: B<$parent> is
the B<full path> of the parent folder (see L<FOLDERS>). B<$name> is the name
of the new folder. B<$use_if_exist> is a boolean parameter. This is only
interesting, when a same-named folder exists on Streamload. If this parameter
is true, the existing folder will be used. If it is false, you will have two
folders with the same name!

To create directory structures, you have to call this function for each folder.
To create a directory Inbox/very/deep/nested, call it this way:

		$sl->ensure_folder("Inbox", "very", 1);
		$sl->ensure_folder("Inbox/very", "deep", 1);
		$sl->ensure_folder("Inbox/very/deep", "nested", 1);

If one of the folders exists, it will be used!

=cut

sub ensure_folder
{
	my ($self, $parent, $name, $use_if_exist) = @_;

	# Check parameters
	croak 'Usage: $p->ensure_folder($parent, $name, $use_if_exist)' if (@_ != 4);
	croak "Parent folder not found!" if (! defined $self->{folders}{$parent});
	croak "No folder name specified!" if ($name eq '');

	# Logged in?
	croak "You are not logged in!" if (! $self->logged_in());

	print "Sending command EnsureFolder...\n" if $DEBUG;

	# Send command
	my $command = pack("VVa*a*C", $cMsgEnsureFolder, length($name), $name,
		$self->{folders}{$parent}, ($use_if_exist != 0));
	$self->send_server($command, length($command));

	# Get response
	my $response = $self->receive_server(1);
	# Was the command successful?
	unpack("C", $response) || $self->_handle_error();

	# Save folder id to hash
	$response = $self->receive_server(8);
	$self->{folders}{$parent."/".$name} = $response;

	print "EnsureFolder succeded!\n" if $DEBUG;
	1;
}

=item $sl->upload($parent, $file, $use_if_exist, \&status_sub);

Upload a file to Streamload. The function takes four parameters: B<$parent> is
the folder on Streamload you want the file to be saved in. B<$file> is the
filename of a local file you want to transfer to Streamload. B<$use_if_exist>
decides whether to overwrite an existing file on Streamload or to create a new
one with the same name! With B<\&status_sub> you can specify a sub, which is
called to inform the calling program about the status of the transfer (see
L<STATUS SUB>).

=cut

sub upload
{
	my ($self, $parent, $file, $use_if_exist, $status_sub) = @_;

	# Check parameters
	croak 'Usage: $p->upload($parent, $file, $use_if_exist, \\&status_sub)' if (@_ != 5);
	croak "Parent folder not found!" if (! defined $self->{folders}{$parent});
	croak "Not a regular file: \"$file\"" unless (-f $file);

	my $filesize = -s $file;
	croak "File \"$file\" could not be read!" if (!$filesize && -r $file);

	# Logged in?
	croak "You are not logged in!" if (! $self->logged_in());

	print "Sending command UploadInit...\n" if $DEBUG;

	my $media_id = $self->_generate_media_id($file);

	# Don't expose client's file structure
	my $filename = (split("/", $file))[-1];
	# Send command (ll (2x 32-bit) as synonym for q (64-bit) with 2. part = 0)
	my $command = pack("Va*Va*Va*VVC", $cMsgUploadInit, $self->{folders}{$parent},
		length($media_id), $media_id, length($filename), $filename, $filesize, 0,
		($use_if_exist != 0));
	$self->send_server($command, length($command));

	open(FILE, "<$file") or croak "Can't open '$file': $!";
	binmode(FILE);

	# Success -> UpStreamload, No Success -> normal Upload
	my $response = $self->receive_server(1);
	my $type = unpack("C", $response);
	if ($type) {
		# UpStreamload
		my $buffer = "";

		# Read key size and key count
		$response = $self->receive_server(8);
		my ($keysize, $keycount) = unpack("V*",$response);

		# Get keys and read the positions in the file...
		for (my $i = 1; $i <= $keycount; $i++) {
			$response = $self->receive_server(8);
			my $pos = unpack("V",$response);
			sysseek(FILE, $pos, 0);  # SEEK_SET
			sysread(FILE, $response, $keysize);
			$buffer .= $response;
		}

		# Send all keys to the server
		$self->send_server($buffer, length($buffer));
	} else {
		# normal Upload
		my $buffer;
		my $bytes_send = 0;
		# Report status (we are at the beginning!)...
		$status_sub->($file, "Upload", 0, $bytes_send, $filesize);
		my $nowread = sysread(FILE, $buffer, $self->{Buffersize});
		while ($nowread != 0) {
			$self->send_server($buffer, $nowread);
			$bytes_send += $nowread;
			# Report status...
			$status_sub->($file, "Upload", 0, $bytes_send, $filesize);
			$nowread = sysread(FILE, $buffer, $self->{Buffersize});
		}
	}
	close(FILE);

	# Read progress of processing
	my $progress;
	# Report status (we are at the beginning!)...
	$status_sub->($file, ($type) ? "UpStreamload" : "Upload", 1, 0, 100);
	do {
		# Check success
		$response = $self->receive_server(1);
		unpack("C", $response) || $self->_handle_error();

		# Read progress (32-bit integer)
		$response = $self->receive_server(4);
		$progress = unpack("V", $response);
		# Report status...
		$status_sub->($file, ($type) ? "UpStreamload" : "Upload", 1,
			($progress != 0) ? $progress : 100, 100);
	} until ($progress == 0);

	# Check success
	$response = $self->receive_server(1);
	unpack("C", $response) || $self->_handle_error();

	print "Upload succeded!\n" if $DEBUG;

	# Return new node ID
	$self->receive_server(8);
}

=item $sl->url_streamload($parent, $url, $use_if_exist, \&status_sub);

Transfer a file from any website to Streamload. B<$parent> is the folder on
Streamload you want the file to be saved in. B<$url> is the URL of a media
file on the Web. Should work with "http://..." and "ftp://...".
B<$use_if_exist> decides whether to overwrite an existing file on Streamload
or to create a new one with the same name! With B<\&status_sub> you can
specify a sub, which is called to inform the calling program about the status
of the transfer(see L<STATUS SUB>).

=cut

sub url_streamload
{
	my ($self, $parent, $url, $use_if_exist, $status_sub) = @_;

	# Check parameters
	croak 'Usage: $p->url_streamload($parent, $url, $use_if_exist, \\&status_sub)' if (@_ != 5);
	croak "Parent folder not found!" if (! defined $self->{folders}{$parent});
	croak "No URL specified!" if ($url eq '');

	# Logged in?
	croak "You are not logged in!" if (! $self->logged_in());

	print "Sending command URLStreamload...\n" if $DEBUG;

	# Send command
	my $command = pack("Va*Va*C", $cMsgURLStreamload, $self->{folders}{$parent},
		length($url), $url, ($use_if_exist != 0));
	$self->send_server($command, length($command));

	# Was the command successful?
	my $response = $self->receive_server(1);
	unpack("C", $response) || $self->_handle_error();

	# Should be a 64-bit integer...
	$response = $self->receive_server(8);
	my $filesize = unpack("V", $response);

	foreach my $i (0..1) {
		my $progress;
		my $maxprogress = ($i) ? 100 : $filesize;
		# Report status (we are at the beginning!)...
		$status_sub->($url, "URLStreamload", $i, 0, $maxprogress);
		do {
			# Check success
			$response = $self->receive_server(1);
			unpack("C", $response) || $self->_handle_error();

			# Read progress (First run -> 64-bit integer, 2. run -> 32-bit integer)
			$response = $self->receive_server(4 * (2 - $i));
			$progress = unpack("V", $response);
			# Report status...
			$status_sub->($url, "URLStreamload", $i,
				($progress != 0) ? $progress : $maxprogress, $maxprogress);
		} until ($progress == 0);
	}
	# Check success
	$response = $self->receive_server(1);
	unpack("C", $response) || $self->_handle_error();

	print "URLStreamload succeded!\n" if $DEBUG;

	# Return new node ID
	$self->receive_server(8);
}

=item $sl->logout();

Logout from Streamload. Yes, I simply close the connection!

=back

=cut

sub logout
{
	my $self = shift;
	close($self->{server}) if $self->logged_in();
	$self->{connected} = 0;
}

sub DESTROY
{
	my $self = shift;
	$self->logout();
}

sub _handle_error
{
	my $self = shift;

	# Length of error message
	my $response = $self->receive_server(4);
	# Read error message
	$response = $self->receive_server(unpack("V", $response));
	croak "Server Error: $response";
}

sub _generate_media_id
{
	my ($self, $file) = @_;

	open(FILE, $file) or croak "Can't open '$file': $!";
	binmode(FILE);
	my $digest = Digest::MD5->new->addfile(*FILE)->digest;
	close FILE;
	join(" ", -s $file, unpack("C*", $digest));
}

# Send same raw data to the server
# Params:
#	$data	The data which is sent
#	$len	Length of the data
# Returns: Length of data actually written
sub send_server($$$)
{
	my ($self, $data, $len) = @_;

	my $ret = syswrite($self->{server}, $data, $len);
	if (!defined($ret)) {
		# Save error message here, because logout could set another
		my $err = "$!";
		$self->logout();
		croak "Could not send: $err";
	}
	$ret;
}

# Receive some data from the server
# Params:
#	$len	How many bytes to be read
# Returns: The data that was read
sub receive_server($$)
{
	my ($self, $len) = @_;

	my $data;
	my $ret = sysread($self->{server}, $data, $len);
	if (!defined($ret)) {
		# Save error message here, because logout could set another
		my $err = "$!";
		$self->logout();
		croak "Could not receive: $err";
	}

	$data;
}

1;

__END__

=head1 INTERNAL STRUCTURES

This explains some of the internal structures of Streamload and this module.
It may be really helpful...

=head2 FOLDERS

Streamload uses IDs for the folders on the server. If you are using this Perl
module, you don't have to care about this. You can call every folder by it's
name. After the login, only the three root folders ("My Stuff", "Inbox" and
"Playlists") are avalible. Now you can use ensure_folder to make other folders
avalible. The new folders can be accessed by their full path (the path
separator is "/" [a slash]), e.g. if you create a new folder "New Folder" in
your "Inbox", it's path will be "Inbox/New Folder". This path can be given to
C<ensure_folder>, C<upload> and C<url_streamload> to be a new B<$parent>.

The IDs of the three root folders and the ID of every folder you query with
ensure_folder are stored in the internal hash $folders. If you want to use
them, you can read this hash ($sl->{folders}) and work with it. But please:
Don't change it!

=head2 STATUS SUB

When you call some functions, you must specify a status sub. This is to inform
your program, how much of the Upload or Download is done. The status sub is
called with four arguments:

	status_sub($file, $action, $stage, $progress, $maxprogress)

Here is a explaination of the arguments: B<$file> is the actual name of the
file that is up- or sownloaded. B<$action> is the action, which is
currently performed. At the moment, it may be "Upload", "UpStreamload" or
"URLStreamload". B<$stage> can be 0 or 1. If it is 0, the up- or download is
running. If it is 1, the server is processing the file. B<$progress> is the
progress of the current action. Normally these are the transfered bytes or
the percentage of the progressing. B<$maxprogress> is the maximum value
$progress can reach.

The simplest way to inform the user would be to write this informations to the
console. But you want to write a nice-looking program, won't you? ;-)

=head1 AUTHOR

Tobias Gruetzmacher, streamload-support@portfolio16.de

=head1 SEE ALSO

http://www.streamload.com/

=cut

# vi: set tabstop=4 shiftwidth=4:
