#! /usr/bin/perl

# (c) 14 aug 2024 mk@mat.ethz.ch 

sub USAGE { print<<EOF;
________________________________________________________________________________
\nThis script requires the existence of two files generated by Z1+, when called with the -SP+ (or +) option: 

1) Z1+initconfig.dat (this file $exin in the current folder)
2) Z1+SP.dat (this file $exSP in the current folder)

Command syntax: 

perl $0 <ChainId> [-folded] [-txt] [-dat] [-SP] [-ee] [-o=..]

Upon entering a chain ID, the script generates a lammps-formatted data file 
(format: id mol type x y z, no charges) that contains the selected chain along with all 
chains entangled with it. Note that the generated data file contains unfolded coordinates
by default. In this new data file, all atoms and bonds of the original chains have type 1.
By default, the name of the created data file is entangled-with-chain-<ChainId>.data
If the script is called without arguments, it returns the following description.

ChainID
    A number between 1 and number of chains present in your system.
-folded 
    If you prefer to create a data file with folded coordinates, add the -folded option. 
-txt
    If you prefer to have the coordinates saved in txt-format, add the -txt option.
-dat
    Instead of creating a lammps data file, create two files using the .dat-format.
    Z1+initconfig-chain=ChainID.dat contains the coordinates of the original chains, 
    Z1+SP-chain=ChainID.dat contains the coordinates of the corresponding shortest paths. 
-SP
    Add the shortest paths of all chains (atom and bond type 2) to the created data file.
-ee
    Add the end-to-end bonds (bond type 3) to the created data file.
-o=<filename>
    Write the data file to <filename> instead of using the default. 

$message

________________________________________________________________________________
EOF
exit; 
};

$in = "Z1+initconfig.dat";
$SP = "Z1+SP.dat";
$savetxt = 0; 
$savedata = 1; 
$savedat = 0; 

sub green { "\033[1;32;40m$_[0]\033[1;37;40m"; };
sub red   { "\033[1;31;40m$_[0]\033[1;37;40m"; };

if (-s "$in") { $exin=green("exists"); } else { $exin=red("missing"); $bad=1; }; 
if (-s "$SP") { $exSP=green("exists"); } else { $exSP=red("missing"); $bad=1; }; 

sub strip { chomp $_[0]; $_[0]=~s/^\s+//g; $_[0]=~s/\s+$//; $_[0]=~s/\s+/ /g; $_[0]; };
sub round { $_[0]+=0; if ($_[0] eq 0) { } else { $_[0]=($_[0]/abs($_[0]))*int(abs($_[0])+0.5); }; $_[0]; };

# read initial configuration
if (-s "$in") { 
open(IN,"<$in"); 
$chains=<IN>+0;
$BOX=<IN>; $BOX=strip($BOX); ($boxx,$boxy,$boxz)=split(/ /,$BOX);
$message="Choose a chain id between 1 and $chains in your call like:\nperl $0 $chains";
if ($#ARGV eq -1) { USAGE; }; 
$xlo=-$boxx/2; $xhi=-$xlo;
$ylo=-$boxy/2; $yhi=-$ylo;
$zlo=-$boxz/2; $zhi=-$zlo;
print "$chains chains, box sizes $boxx $boxy $boxz\n";
foreach $c (1 .. $chains) {
    $N[$c]=<IN>+0;
    foreach $b (1 .. $N[$c]) {
        $line=<IN>; $line=strip($line); 
        ($x[$c][$b],$y[$c][$b],$z[$c][$b])=split(/ /,$line);
    };  
};
close(IN);
}; 

if ($bad eq 1) { USAGE; };

foreach $iarg (0 .. $#ARGV)     { $arg=$ARGV[$iarg]; ($field,$value)=split(/=/,$arg);
    if ($arg eq "-folded")      { $folded=1; 
    } elsif ($arg eq "-txt")    { $savetxt=1; $savedata=0; 
    } elsif ($arg eq "-dat")    { $savedat=1; $savedata=0; $addSP=1; 
    } elsif ($arg eq "-SP")     { $addSP=1; 
    } elsif ($arg eq "-ee")     { $addEE=1; 
    } elsif ($field eq "-o")    { $data="$value"; 
    } elsif ($iarg>0)           { $message = red("Unknown argument $arg\n"); USAGE; };  
};

# read shortest paths
open(SP,"<$SP"); 
$chainsSP=<SP>+0; if ($chains != $chainsSP) { print "incompatible files $in and $SP!\n"; exit; }; 
$BOX=<SP>; $BOX=strip($BOX); ($boxx,$boxy,$boxz)=split(/ /,$BOX);
foreach $c (1 .. $chains) {
    $NSP[$c]=<SP>+0;
    $Z[$c] = 0;
    foreach $b (1 .. $NSP[$c]) {
        $line=<SP>; $line=strip($line);
        ($xSP[$c][$b],$ySP[$c][$b],$zSP[$c][$b],$pos[$c][$b],$ent[$c][$b],$entc[$c][$b],$entb[$c][$b])=split(/ /,$line);
        $Z[$c] += $ent[$c][$b];
        if (($b eq 2)&(!$entc[$c][$b])&($Z[$c]>0)) { 
            $message = red("You do not have the proper Z1+SP.dat file. Call Z1+ with the -SP+ option to create it!"); USAGE; 
        }; 
    };
    if ($c < 10) { print "chain id $c has $Z[$c] entanglements\n"; }; 
    if ($c eq $chains) { print "...\nchain $c has $Z[$c] entanglements\n"; };
};
close(SP);

$selected = int($ARGV[0]); 
if (($selected < 0)|($selected > $chains)) { $message=red("Chain id $selected does not exist in your files"); USAGE; }; 
if ($Z[$selected] eq 0) { $message=red("Chain id $selected does not have any entanglements"); USAGE; }; 

# create folded/unfolded original coordinates of selected chain
$id=1; $bid=0; 
$atomtypes = 1; 
$bondtypes = 1; 
$OUT="$id $selected 1 $x[$selected][1] $y[$selected][1] $z[$selected][1]\n";
$OUTDAT="$N[$selected]\n$x[$selected][1] $y[$selected][1] $z[$selected][1]\n"; 
$xhi = $x[$selected][1]; $xlo = $xhi;
$yhi = $y[$selected][1]; $ylo = $yhi;
$zhi = $z[$selected][1]; $zlo = $zhi;
$EE1[$#EE1+1] = $id; 
foreach $b (2 .. $N[$selected]) {
    $id+=1; 
    $ux = $x[$selected][$b]-$x[$selected][$b-1]; $ux -= $boxx*round($ux/$boxx);
    $uy = $y[$selected][$b]-$y[$selected][$b-1]; $uy -= $boxy*round($uy/$boxy);
    $uz = $z[$selected][$b]-$z[$selected][$b-1]; $uz -= $boxz*round($uz/$boxz);
    $xu = $x[$selected][$b-1]+$ux; 
    $yu = $y[$selected][$b-1]+$uy;
    $zu = $z[$selected][$b-1]+$uz;
    if ($folded) {
        $ix = round($xu/$boxx);
        $iy = round($yu/$boxy); 
        $iz = round($zu/$boxz);
        $xx = $xu - $boxx*$ix;
        $yy = $yu - $boxy*$iy;
        $zz = $zu - $boxz*$iz;
        $OUT.="$id $selected 1 $xx $yy $zz $ix $iy $iz\n";
        $OUTDAT.="$xx $yy $zz\n";
    } else { 
        $OUT.="$id $selected 1 $xu $yu $zu 0 0 0\n";
        $OUTDAT.="$xu $yu $zu\n"; 
        if ($xu > $xhi) { $xhi = $xu; }; 
        if ($yu > $yhi) { $yhi = $yu; };
        if ($zu > $zhi) { $zhi = $zu; };
        if ($xu < $xlo) { $xlo = $xu; };
        if ($yu < $ylo) { $ylo = $yu; };
        if ($zu < $zlo) { $zlo = $zu; };
    };
    $bid+=1; 
    $id0=$id-1;
    $BOUT.="$bid 1 $id0 $id\n";
};
$EE2[$#EE2+1] = $id;
if (!$folded) { print "revised xlo xhi .. zlo: $xlo $xhi $ylo $yhi $zlo $zhi so that the box contains the unfolded chains.\n"; }; 

# create folded/unfolded original coordinates of entanged chains
if (!$data) { $data = "entangled-with-chain-$selected.data"; };
print green("now creating lammps data file for selected chain id $selected ..\n");
@ENTANGLED=(); @SHIFTX=(); @SHIFTY=(); @SHIFTZ=(); @REVERSE=(); $REVERSE[$selected]=1; 
foreach $b (2 .. $NSP[$selected]-1) { 
    $entangled = $entc[$selected][$b];
    $ENTANGLED[$#ENTANGLED+1] = $entangled; 
    $REVERSE[$entangled] = $#ENTANGLED+2; 
    print "adding entangled chain pair ($selected <-> $entangled)\n"; 

    foreach $beadshift (0 .. 1) { 
        $ux = $xSP[$entangled][$beadshift+$entb[$selected][$b]]-$xSP[$selected][$b];
        $uy = $ySP[$entangled][$beadshift+$entb[$selected][$b]]-$ySP[$selected][$b];
        $uz = $zSP[$entangled][$beadshift+$entb[$selected][$b]]-$zSP[$selected][$b];
        $shiftx = $boxx*round($ux/$boxx); 
        $shifty = $boxy*round($uy/$boxy); 
        $shiftz = $boxz*round($uz/$boxz); 
        $ux -= $shiftx;
        $uy -= $shifty;
        $uz -= $shiftz;
        $distance[$beadshift] = sqrt($ux*$ux+$uy*$uy+$uz*$uz); 
    }; 
    if ($distance[0]<$distance[1]) {
        $beadshift = 0;
    } else {
        $beadshift = 1; 
    }; 
    $ux = $xSP[$entangled][$beadshift+$entb[$selected][$b]]-$xSP[$selected][$b];
    $uy = $ySP[$entangled][$beadshift+$entb[$selected][$b]]-$ySP[$selected][$b];
    $uz = $zSP[$entangled][$beadshift+$entb[$selected][$b]]-$zSP[$selected][$b];
    $shiftx = $boxx*round($ux/$boxx); $SHIFTX[$#SHIFTX+1] = -$shiftx;
    $shifty = $boxy*round($uy/$boxy); $SHIFTY[$#SHIFTY+1] = -$shifty;
    $shiftz = $boxz*round($uz/$boxz); $SHIFTZ[$#SHIFTZ+1] = -$shiftz;
    $ux -= $shiftx;
    $uy -= $shifty;
    $uz -= $shiftz;
    $distance = sqrt($ux*$ux+$uy*$uy+$uz*$uz);

    # print "SHIFT [entangled no $#ENTANGLED - original $entangled] $SHIFTX[$#SHIFTX] $SHIFTY[$#SHIFTY] $SHIFTZ[$#SHIFTZ]\n";
    $id+=1;
    $xs = $x[$entangled][1] + $shiftx; 
    $ys = $y[$entangled][1] + $shifty;
    $zs = $z[$entangled][1] + $shiftz;
    $EE1[$#EE1+1] = $id;
    if ($folded) { 
        $ix = round($xs/$boxx);
        $iy = round($ys/$boxy);
        $iz = round($zs/$boxz);
        $xx = $xs - $boxx*$ix;
        $yy = $ys - $boxy*$iy;
        $zz = $zs - $boxz*$iz;
        $OUT.="$id $entangled 1 $xx $yy $zz $ix $iy $iz\n";
        $OUTDAT.="$N[$entangled]\n$xx $yy $zz\n";
    } else { 
        $OUT.="$id $entangled 1 $xs $ys $zs 0 0 0\n";
        $OUTDAT.="$N[$entangled]\n$xs $ys $zs\n";
    }; 
    foreach $be (2 .. $N[$entangled]) {
        $id+=1;
        $xs = $x[$entangled][$be] + $shiftx;
        $ys = $y[$entangled][$be] + $shifty;
        $zs = $z[$entangled][$be] + $shiftz; 
        if ($folded) {
            $ix = round($xs/$boxx);
            $iy = round($ys/$boxy);
            $iz = round($zs/$boxz);
            $xx = $xs - $boxx*$ix;
            $yy = $ys - $boxy*$iy;
            $zz = $zs - $boxz*$iz;
            $OUT.="$id $entangled 1 $xx $yy $zz $ix $iy $iz\n";
            $OUTDAT.="$xx $yy $zz\n";
        } else { 
            $OUT.="$id $entangled 1 $xs $ys $zs 0 0 0\n";
            $OUTDAT.="$xs $ys $zs\n";
        }; 
        $bid+=1; 
        $id0=$id-1; 
        $BOUT.="$bid 1 $id0 $id\n";
    };        
    $EE2[$#EE2+1] = $id; 
};

# create folded/unfolded SP of selected chain
if ($addSP) { 
$id+=1; $selected_SP = $selected+$chains; 
$atomtypes = 2; 
$bondtypes = 2; 
$OUT.="$id $selected_SP 2 $xSP[$selected][1] $ySP[$selected][1] $zSP[$selected][1]\n";
$ENTC = $REVERSE[$entc[$selected][1]]; 
$OUTDATSP.="$NSP[$selected]\n$xSP[$selected][1] $ySP[$selected][1] $zSP[$selected][1] $pos[$selected][1] $ent[$selected][1] $ENTC $entb[$selected][1]\n";
foreach $b (2 .. $NSP[$selected]) {
    $id+=1;
    $ux = $xSP[$selected][$b]-$xSP[$selected][$b-1]; $ux -= $boxx*round($ux/$boxx);
    $uy = $ySP[$selected][$b]-$ySP[$selected][$b-1]; $uy -= $boxy*round($uy/$boxy);
    $uz = $zSP[$selected][$b]-$zSP[$selected][$b-1]; $uz -= $boxz*round($uz/$boxz);
    $xu = $xSP[$selected][$b-1]+$ux;
    $yu = $ySP[$selected][$b-1]+$uy;
    $zu = $zSP[$selected][$b-1]+$uz;
    if ($folded) {
        $ix = round($xu/$boxx);
        $iy = round($yu/$boxy);
        $iz = round($zu/$boxz);
        $xx = $xu - $boxx*$ix;
        $yy = $yu - $boxy*$iy;
        $zz = $zu - $boxz*$iz;
        $OUT.="$id $selected_SP 2 $xx $yy $zz $ix $iy $iz\n";
        $ENTC = $REVERSE[$entc[$selected][$b]]; if ((!$ENTC)&&($b<$NSP[$selected])) { $ENTC="-1"; };
        $OUTDATSP.="$xx $yy $zz $pos[$selected][$b] $ent[$selected][$b] $ENTC $entb[$selected][$b]\n";
    } else {
        $OUT.="$id $selected_SP 2 $xu $yu $zu 0 0 0\n";
        $ENTC = $REVERSE[$entc[$selected][$b]]; if ((!$ENTC)&&($b<$NSP[$selected])) { $ENTC="-1"; };
        $OUTDATSP.="$xu $yu $zu $pos[$selected][$b] $ent[$selected][$b] $ENTC $entb[$selected][$b]\n";
    };
    $bid+=1;
    $id0=$id-1;
    $BOUT.="$bid 2 $id0 $id\n";
};
};

# created folded/unfolded SP of entangled SP
if ($addSP) { 
foreach $no (0 .. $#ENTANGLED) {
    $entangled = $ENTANGLED[$no]; 
    $entangled_SP = $entangled + $chains;
    $id+=1;
    $xs = $xSP[$entangled][1] + $SHIFTX[$no];
    $ys = $ySP[$entangled][1] + $SHIFTY[$no];  # 21 aug 2024
    $zs = $zSP[$entangled][1] + $SHIFTZ[$no];
    if ($folded) {
        $ix = round($xs/$boxx);
        $iy = round($ys/$boxy);
        $iz = round($zs/$boxz);
        $xx = $xs - $boxx*$ix;
        $yy = $ys - $boxy*$iy;
        $zz = $zs - $boxz*$iz;
        $OUT.="$id $entangled_SP 2 $xx $yy $zz $ix $iy $iz\n";
        $ENTC = $REVERSE[$entc[$entangled][1]]; 
        $OUTDATSP.="$NSP[$entangled]\n$xx $yy $zz $pos[$entangled][1] $ent[$entangled][1] $ENTC $entb[$entangled][1]\n";
    } else {
        $OUT.="$id $entangled_SP 2 $xs $ys $zs 0 0 0\n";
        $ENTC = $REVERSE[$entc[$entangled][1]]; 
        $OUTDATSP.="$NSP[$entangled]\n$xs $ys $zs $pos[$entangled][1] $ent[$entangled][1] $ENTC $entb[$entangled][1]\n";
    };
    foreach $be (2 .. $NSP[$entangled]) {
        $id+=1;
        $xs = $xSP[$entangled][$be] + $SHIFTX[$no];
        $ys = $ySP[$entangled][$be] + $SHIFTY[$no];
        $zs = $zSP[$entangled][$be] + $SHIFTZ[$no];
        if ($folded) {
            $ix = round($xs/$boxx);
            $iy = round($ys/$boxy);
            $iz = round($zs/$boxz);
            $xx = $xs - $boxx*$ix;
            $yy = $ys - $boxy*$iy;
            $zz = $zs - $boxz*$iz;
            $OUT.="$id $entangled_SP 2 $xx $yy $zz $ix $iy $iz\n";
            $ENTC = $REVERSE[$entc[$entangled][$be]]; if ((!$ENTC)&($be<$NSP[$entangled])) { $ENTC="-1"; };
            $OUTDATSP.="$xx $yy $zz $pos[$entangled][$be] $ent[$entangled][$be] $ENTC $entb[$entangled][$be]\n";
        } else {
            $OUT.="$id $entangled_SP 2 $xs $ys $zs 0 0 0\n";
            $ENTC = $REVERSE[$entc[$entangled][$be]]; if ((!$ENTC)&($be<$NSP[$entangled])) { $ENTC="-1"; };
            $OUTDATSP.="$xs $ys $zs $pos[$entangled][$be] $ent[$entangled][$be] $ENTC $entb[$entangled][$be]\n";
        };
        $bid+=1;
        $id0=$id-1;
        $BOUT.="$bid 2 $id0 $id\n";
    };
};
};
 
# add end-to-end bonds
if ($addEE) {
    $bondtypes = 3; 
    foreach $ib (0 .. $#EE1) { 
        $bid+=1; 
        $BOUT.="$bid 3 $EE1[$ib] $EE2[$ib]\n";
    };
};

# save lammps data file
if ($savedata) { 
open(OUT,">$data"); 
print OUT<<EOF;
lammps data file generated via $0 $selected\n
$id atoms
$bid bonds
$atomtypes atom types
$bondtypes bond types

$xlo $xhi xlo xhi
$ylo $yhi ylo yhi
$zlo $zhi zlo zhi
\nAtoms\n
$OUT
Bonds\n
$BOUT
EOF
close(OUT);
print green("created $data ($id atoms, $chains chains, $bid bonds, $atomtypes atom types, $bondtypes bond types)\n");
}; 

# save dat-files
if ($savedat) {
$entangled_chains = $#ENTANGLED+1; 
$chains_in_dat_file = $entangled_chains+1; 
open(OUT,">Z1+initconfig-chain=$selected.dat"); print OUT<<EOF;
$chains_in_dat_file
$boxx $boxy $boxz
$OUTDAT
EOF
close(OUT);
open(OUT,">Z1+SP-chain=$selected.dat"); print OUT<<EOF;
$chains_in_dat_file
$boxx $boxy $boxz
$OUTDATSP
EOF
close(OUT);
print green("created Z1+initconfig-chain=$selected.dat and Z1+SP-chain=$selected.dat.\n($id atoms, $chains chains, $bid bonds, $atomtypes atom types, $bondtypes bond types)\n");
};

# for non-ovito users: 
if ($savetxt) { 
    $txt = "entangled-with-chain-$selected.txt"; open(OUT,">$txt"); print OUT $OUT; close(OUT); 
    print green("created $txt\n"); 
}; 

