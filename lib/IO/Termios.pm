#  You may distribute under the terms of either the GNU General Public License
#  or the Artistic License (the same terms as Perl itself)
#
#  (C) Paul Evans, 2008-2011 -- leonerd@leonerd.org.uk

package IO::Termios;

use strict;
use warnings;
use base qw( IO::Handle );

use Carp;

our $VERSION = '0.03';

use Exporter 'import';

use POSIX qw( TCSANOW );

=head1 NAME

C<IO::Termios> - supply F<termios(3)> methods to C<IO::Handle> objects

=head1 SYNOPSIS

 use IO::Termios;

 my $term = IO::Termios->open( "/dev/ttyS0", "9600,8,n,1" )
    or die "Cannot open ttyS0 - $!";

 $term->print( "Hello world\n" ); # Still an IO::Handle

 while( <$term> ) {
    print "A line from ttyS0: $_";
 }

=head1 DESCRIPTION

This class extends the generic C<IO::Handle> object class by providing methods
which access the system's terminal control C<termios(3)> operations.

=cut

=head1 CONSTRUCTORS

=cut

=head2 $term = IO::Termios->new()

Construct a new C<IO::Termios> object around the terminal for the program.
This is found by checking if any of C<STDIN>, C<STDOUT> or C<STDERR> are a
terminal. The first one that's found is used. An error occurs if no terminal
can be found by this method.

=head2 $term = IO::Termios->new( $handle )

Construct a new C<IO::Termios> object around the given filehandle.

=cut

sub new
{
   my $class = shift;
   my ( $handle ) = @_;

   if( not $handle ) {
      # Try to find a terminal - STDIN, STDOUT, STDERR are good candidates
      return $class->SUPER::new_from_fd( fileno STDIN,  "w+" ) if -t STDIN;
      return $class->SUPER::new_from_fd( fileno STDOUT, "w+" ) if -t STDOUT;
      return $class->SUPER::new_from_fd( fileno STDERR, "w+" ) if -t STDERR;

      die "TODO: Need to find a terminal\n";
   }

   croak '$handle is not a filehandle' unless defined fileno $handle;

   my $self = $class->SUPER::new_from_fd( $handle, "w+" );

   return $self;
}

=head2 $term = IO::Termios->open( $path, $modestr )

Open the given path, and return a new C<IO::Termios> object around the
filehandle. If the C<open> call fails, C<undef> is returned.

If C<$modestr> is provided, the constructor will pass it to the C<set_mode>
method before returning.

=cut

sub open
{
   my $class = shift;
   my ( $path, $modestr ) = @_;

   open my $tty, "+<", $path or return undef;
   my $self = $class->new( $tty ) or return undef;

   $self->set_mode( $modestr ) if defined $modestr;

   return $self;
}

=head1 METHODS

=cut

=head2 $attrs = $term->getattr

Makes a C<tcgetattr()> call on the underlying filehandle, and returns a
C<IO::Termios::Attrs> object.

If the C<tcgetattr()> call fails, C<undef> is returned.

=cut

sub getattr
{
   my $self = shift;

   my $attrs = IO::Termios::Attrs->new;
   $attrs->getattr( $self->fileno ) or return undef;

   return $attrs;
}

=head2 $term->setattr( $attrs )

Makes a C<tcsetattr()> call on the underlying file handle, setting attributes
from the given C<IO::Termios::Attrs> object.

If the C<tcsetattr()> call fails, C<undef> is returned. Otherwise, a true
value is returned.

=cut

sub setattr
{
   my $self = shift;
   my ( $attrs ) = @_;

   return $attrs->setattr( $self->fileno, TCSANOW );
}

=head1 FLAG-ACCESSOR METHODS

Theses methods are implemented in terms of the lower level methods, but
provide an interface which is more abstract, and easier to re-implement on
other non-POSIX systems. These should be used in preference to the lower ones.

For efficiency, when getting or setting a large number of flags, it may be
more efficient to call C<getattr>, then operate on the returned object,
before possibly passing it to C<setattr>. The returned C<IO::Termios::Attrs>
object supports the same methods as documented here.

The following two sections of code are therefore equivalent, though the latter
is more efficient as it only calls C<setattr> once.

 $term->setbaud( 38400 );
 $term->setcsize( 8 );
 $term->setparity( 'n' );
 $term->setstop( 1 );

Z<>

 my $attrs = $term->getattr;
 $attrs->setbaud( 38400 );
 $attrs->setcsize( 8 );
 $attrs->setparity( 'n' );
 $attrs->setstop( 1 );
 $term->setattr( $attrs );

However, a convenient shortcut method is provided for the common case of
setting the baud rate, character size, parity and stop size all at the same
time. This is C<set_mode>:

 $term->set_mode( "38400,8,n,1" );

=cut

=head2 $baud = $term->getibaud

=head2 $baud = $term->getobaud

=head2 $term->setibaud( $baud )

=head2 $term->setobaud( $baud )

=head2 $term->setbaud( $baud )

Convenience accessors for the C<ispeed> and C<ospeed>. C<$baud> is an integer
directly giving the line rate, instead of one of the C<BI<nnn>> constants.

=head2 $bits = $term->getcsize

=head2 $term->setcsize( $bits )

Convenience accessor for the C<CSIZE> bits of C<c_cflag>. C<$bits> is an
integer 5 to 8.

=head2 $parity = $term->getparity

=head2 $term->setparity( $parity )

Convenience accessor for the C<PARENB> and C<PARODD> bits of C<c_cflag>.
C<$parity> is C<n>, C<o> or C<e>.

=head2 $stop = $term->getstop

=head2 $term->setstop( $stop )

Convenience accessor for the C<CSTOPB> bit of C<c_cflag>. C<$stop> is 1 or 2.

=cut

foreach my $name (qw( ibaud obaud csize parity stop )) {
   my $getmethod = "get$name";
   my $setmethod = "set$name";

   no strict 'refs';
   *$getmethod = sub {
      my ( $self ) = @_;
      my $attrs = $self->getattr or croak "Cannot getattr - $!";
      return $attrs->$getmethod;
   };
   *$setmethod = sub {
      my ( $self, $val ) = @_;
      my $attrs = $self->getattr or croak "Cannot getattr - $!";
      $attrs->$setmethod( $val );
      $self->setattr( $attrs ) or croak "Cannot setattr - $!";
   };
}

*setbaud = sub {
   my ( $self, $val ) = @_;
   my $attrs = $self->getattr or croak "Cannot getattr - $!";
   $attrs->setbaud( $val );
   $self->setattr( $attrs ) or croak "Cannot setattr - $!";
};

=head2 $mode = $term->getflag_cread

=head2 $term->setflag_cread( $mode )

Accessor for the C<CREAD> bit of the C<c_cflag>. This enables the receiver.

=head2 $mode = $term->getflag_hupcl

=head2 $term->setflag_hupcl( $mode )

Accessor for the C<HUPCL> bit of the C<c_cflag>. This lowers the modem control
lines after the last process closes the device.

=head2 $mode = $term->getflag_clocal

=head2 $term->setflag_clocal( $mode )

Accessor for the C<CLOCAL> bit of the C<c_cflag>. This controls whether local
mode is enabled; which if set, ignores modem control lines.

=cut

=head2 $mode = $term->getflag_icanon

=head2 $term->setflag_icanon( $mode )

Accessor for the C<ICANON> bit of C<c_lflag>. This is called "canonical" mode
and controls whether the terminal's line-editing feature will be used to
return a whole line (if false), or if individual bytes from keystrokes will be
returned as they are available (if true).

=cut

=head2 $mode = $term->getflag_echo

=head2 $term->setflag_echo( $mode )

Accessor for the C<ECHO> bit of C<c_lflag>. This controls whether input
characters are echoed back to the terminal.

=cut

my @flags = (
   # cflag
   [ cread  => qw( CREAD  c ) ],
   [ clocal => qw( CLOCAL c ) ],
   [ hupcl  => qw( HUPCL  c ) ],
   # lflag
   [ icanon => qw( ICANON l ) ],
   [ echo   => qw( ECHO   l ) ],
);

foreach ( @flags ) {
   my ( $name ) = @$_;

   my $getmethod = "getflag_$name";
   my $setmethod = "setflag_$name";

   no strict 'refs';
   *$getmethod = sub {
      my ( $self ) = @_;
      my $attrs = $self->getattr or croak "Cannot getattr - $!";
      return $attrs->$getmethod;
   };
   *$setmethod = sub {
      my ( $self, $set ) = @_;
      my $attrs = $self->getattr or croak "Cannot getattr - $!";
      $attrs->$setmethod( $set );
      $self->setattr( $attrs ) or croak "Cannot setattr - $!";
   };
}

=head2 $term->set_mode( $modestr )

=head2 $modestr = $term->get_mode

Accessor for the derived "mode string", which is a comma-joined concatenation
of the baud rate, character size, parity mode, and stop size in a format such
as

 19200,8,n,1

When setting the mode string, trailing components may be omitted meaning their
value will not be affected.

=cut

sub set_mode
{
   my $self = shift;
   my ( $modestr ) = @_;

   my ( $baud, $csize, $parity, $stop ) = split m/,/, $modestr;

   my $attrs = $self->getattr;

   $attrs->setbaud  ( $baud   ) if defined $baud;
   $attrs->setcsize ( $csize  ) if defined $csize;
   $attrs->setparity( $parity ) if defined $parity;
   $attrs->setstop  ( $stop   ) if defined $stop;

   $self->setattr( $attrs );
}

sub get_mode
{
   my $self = shift;

   my $attrs = $self->getattr;
   return join ",",
      $attrs->getibaud,
      $attrs->getcsize,
      $attrs->getparity,
      $attrs->getstop;
}

package # hide from CPAN
   IO::Termios::Attrs;

use base qw( POSIX::Termios );

use Carp;
use POSIX qw( CSIZE CS5 CS6 CS7 CS8 PARENB PARODD CSTOPB );
# IO::Tty has more B<\d> constants than POSIX has
use IO::Tty;

# POSIX::Termios does not respect subclassing
sub new
{
   my $class = shift;
   my $self = $class->SUPER::new;
   bless $self, $class;
   return $self;
}

foreach ( @flags ) {
   my ( $name, $const, $member ) = @$_;

   $const = POSIX->$const();

   my $getmethod = "getflag_$name";
   my $getflag   = "get${member}flag";

   my $setmethod = "setflag_$name";
   my $setflag   = "set${member}flag";

   no strict 'refs';
   *$getmethod = sub {
      my ( $self ) = @_;
      $self->$getflag & $const
   };
   *$setmethod = sub {
      my ( $self, $set ) = @_;
      $set ? $self->$setflag( $self->$getflag |  $const )
           : $self->$setflag( $self->$getflag & ~$const );
   };
}

my %_speed2baud = map { IO::Tty::Constant->${\"B$_"} => $_ } 
   qw( 0 50 75 110 134 150 200 300 600 1200 2400 4800 9600 19200 38400 57600 115200 230400 );
my %_baud2speed = reverse %_speed2baud;

sub getibaud { $_speed2baud{ $_[0]->getispeed } }
sub getobaud { $_speed2baud{ $_[0]->getospeed } }

sub setibaud { $_[0]->setispeed( $_baud2speed{$_[1]} ) }
sub setobaud { $_[0]->setospeed( $_baud2speed{$_[1]} ) }

sub setbaud
{
   my $speed = $_baud2speed{$_[1]};
   $_[0]->setispeed( $speed ) and $_[0]->setospeed( $speed );
}

sub getcsize
{
   my $self = shift;
   my $cflag = $self->getcflag;
   return {
      CS5, 5,
      CS6, 6,
      CS7, 7,
      CS8, 8,
   }->{ $cflag & CSIZE };
}

sub setcsize
{
   my $self = shift;
   my ( $bits ) = @_;
   my $cflag = $self->getcflag;

   $cflag &= ~CSIZE;
   $cflag |= {
      5, CS5,
      6, CS6,
      7, CS7,
      8, CS8,
   }->{ $bits };

   $self->setcflag( $cflag );
}

sub getparity
{
   my $self = shift;
   my $cflag = $self->getcflag;
   return 'n' unless $cflag & PARENB;
   return 'o' if $cflag & PARODD;
   return 'e';
}

sub setparity
{
   my $self = shift;
   my ( $parity ) = @_;
   my $cflag = $self->getcflag;

   $parity eq 'n' ? $cflag &= ~PARENB :
   $parity eq 'o' ? $cflag |= PARENB|PARODD :
   $parity eq 'e' ? ($cflag |= PARENB) &= ~PARODD :
      croak "Unrecognised parity '$parity'";

   $self->setcflag( $cflag );
}

sub getstop
{
   my $self = shift;
   return 2 if $self->getcflag & CSTOPB;
   return 1;
}

sub setstop
{
   my $self = shift;
   my ( $stop ) = @_;
   my $cflag = $self->getcflag;

   $stop == 1 ? $cflag &= ~CSTOPB :
   $stop == 2 ? $cflag |=  CSTOPB :
      croak "Unrecognised stop '$stop'";

   $self->setcflag( $cflag );
}

=head1 TODO

=over 4

=item *

Adding more getflag_*/setflag_* convenience wrappers

=item *

Automatically upgrading STDIN/STDOUT/STDERR if appropriate, given a flag.

 use IO::Termios -upgrade;

 STDIN->setflag_echo( 0 );

=item *

Modem line control, via C<TCIOM{GET,SET,BIS,BIC}>. Annoyingly it doesn't
appear this is available without XS code.

=back

=head1 SEE ALSO

=over 4

=item *

L<IO::Tty> - Import Tty control constants

=back

=head1 AUTHOR

Paul Evans <leonerd@leonerd.org.uk>

=cut

0x55AA;
