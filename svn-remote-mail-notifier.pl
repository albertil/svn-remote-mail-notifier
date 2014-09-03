#!/usr/bin/perl -w
use strict;
use utf8;
use MIME::Lite;
use Cwd 'abs_path';
use Getopt::Long;
use Email::Valid;

my $installPath = abs_path($0);
($installPath) = $installPath =~ /^(.+\/).*$/m;

our $revFile = $installPath . "rev.cfg";

our $repoUrl='';
our $smtpServer='';
our $senderEmail='svn-notifier@noreply.org';
our $recipientEmail='';
our $debug=0;
our $help=0;

sub getDatepattern {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
    return sprintf("%04d-%02d-%02d %02d:%02d:%02d", (1900 + $year), ($mon + 1), $mday, $hour, $min, $sec); 
}

##################################################
# Logs a message if debug is enabled
# params:
#	param1: message to log
sub debug {
    my ($message) = @_;
    print getDatepattern . " : [DEBUG] : $message\n" if $debug;
}

##################################################
# Logs a message
# params:
#	param1: message to log
sub info {
    my ($message) = @_;
    print getDatepattern . " : [INFO] : $message\n";
}


##################################################
# Logs a message and die
# params:
#	param1: message to log
sub logAndDie {
    my ($message) = @_;
    die getDatepattern . " : [FATAL] : $message\n";
}

##################################################
# Send an email to a given email address with a given message
# params:
#	param1: email to contact
#	param2: message to send 
sub sendMail {
	my ($subject, $body) = @_;
	debug "Sending commit info: $subject...";
	my $msg = MIME::Lite->new(
      From    => $senderEmail,
      To      => $recipientEmail,
      Subject => "$subject",
      Type    => "text/plain",
      Data    => $body
    );

    $msg->send;
}

##################################################
# Write a revision number into $revFile
# params:
#	param1: revision number to write
sub writeRevFile {
    my ($rev) = @_;
    open(FILEHANDLER, ">", $revFile) or logAndDie "cannot open $revFile for reading: $!";	
    print FILEHANDLER "$rev\n";
    close(FILEHANDLER);
}

##################################################
# print usage
sub usage {
    print 'svn-remote-mail-notifier.pl --url=<repository_url> --smtp=<smtp_server> --recipient=<recipient_email_address> [--sender=<sender_email_address>] [--debug] [--help]

    --help: displays this help and exits    
    --url: The SVN repository url
    --smtp: SMTP server used to send mail
    --recipient: TO email address
    --sender: FROM email address (optional defaults to "svn-notifier@noreply.org")
    --debug: toggle debug logs on

';
}

##################################################
# Complains against missing parameter
# params:
#	param1: the missing parameter
sub missingMandatoryParam {
    my ($param) = @_;
    print getDatepattern . " : [FATAL] : Missing mandatory parameter \"$param\"\n";
    usage();
    exit(1);
}

##################################################
# Main program


GetOptions ('help!' => \$help, 'debug!' => \$debug, 'url=s' => \$repoUrl, 'smtp=s' => \$smtpServer, 'sender=s' => \$senderEmail, 'recipient=s' => \$recipientEmail);

$repoUrl ne '' or  missingMandatoryParam "url";
$smtpServer ne '' or  missingMandatoryParam("smtp");;
$recipientEmail ne '' or  missingMandatoryParam("recipient");;


Email::Valid->address($senderEmail) or logAndDie "$senderEmail is an invalid email";
Email::Valid->address($recipientEmail) or logAndDie "$recipientEmail is an invalid email";


#Use odin as smtp server
MIME::Lite->send('smtp', $smtpServer);

info "starting svn checking process";
my $result = `svn log $repoUrl -l 1` or logAndDie "SVN command failed: $!";
debug "result:\n$result";

my ($latestRepoRev) = $result =~ /^r(\d+)\s*\|/m or  logAndDie "Can't retrieve latest rev";

debug "latest repo rev $latestRepoRev";

my $latestKnownRev = -1;

if(open(FILEHANDLER, "<", $revFile)) {	
    my @lines = <FILEHANDLER>;
    close(FILEHANDLER);
    $latestKnownRev = $lines[0];
    chomp($latestKnownRev);
    debug "latestKnownRev:\n$latestKnownRev";
} else {
    info "can't open file $revFile for reading. Let's try to initialize it to the latest repository revision: $latestRepoRev.";
    writeRevFile $latestRepoRev;
    exit;
}

if ($latestKnownRev == $latestRepoRev) {
    info "no change on svn";
    exit;
} 

for (my $i = $latestKnownRev + 1; $i <= $latestRepoRev; $i++) {
    my $log = `svn log $repoUrl -r $i` or logAndDie "SVN command failed: $!";
    $log =~ s/^-+$//mg;
    debug "$log";
    # Get commit message
    my ($message) = $log =~ /r$i.+?\n(.+)/s;
    # Get first non empty line
    ($message) = $message =~ /^(.+)$/m;
    debug "-- " . $message . " --";    
    $result = `svn diff -c $i --summarize $repoUrl` or logAndDie "SVN command failed: $!";
    debug "-- " . $result . " --";
    #Get first path
    my ($path) = $result =~ m|$repoUrl(.*)$|m;
    $path = "" unless defined $path;
    debug "-- " . $path . " --";
    $result .= "\n";
    $result .= `svn diff -c $i $repoUrl`;
     
    sendMail("[$i] $path: $message", "$log$result");
}  

writeRevFile $latestRepoRev;
info "svn checking process done";

