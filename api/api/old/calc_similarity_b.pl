#!/usr/bin/perl

use Encode;
use DBI;
use Try::Tiny;
use String::Util 'trim';
use Text::MeCab;
use Math::Trig;
use Time::HiRes qw(gettimeofday);


require("sparql.pl");
require("goal_backend.pl");

#my $graph_uri = "http://collab.open-opinion.org";
my $aninfo_class = "http://data.open-opinion.org/socia-ns#AnnotationInfo";

my $this_soft_agent = "http://collab.open-opinion.org/resource/Person/SimilarGoalRetriever-0.1";

my $dbname = "Goalshare";
my $dbUser = "gsuser";
my $dbPassword = "goalshare";

my $IDF_LIMIT = 2.3;  # lower limit fot IDF (inverse document frequency)
my $FILTER_THRESHOLD = 0.05;  # threshold of the BoF element to filter candidate goals by included features
my $SIM_THRESHOLD = 0.6; # threshold of the similarity for linking goals 

my $WEIGHT_BOW = 0.5;              # alpha: weight of BoW (Bag-of-Words)
my $WEIGHT_BOT = 1 - $WEIGHT_BOW;  # beta: weight of BoT (Bag-of-Topics)

# Parameters for building BoF (Bag-of-Features)
# weight of Context-BoF: $WEIGHT_CONTEXT_MAX * tanh($COEF_TANH * (norm of Context-BoF))
# weight of Self-BoF   : 1 - (weight of Context-BoF)
my $WEIGHT_CONTEXT_MAX = 0.5; # maximum of the weight of Context-BoF
my $COEF_TANH = 0.7;          # coefficient for tanh curve to determine the weight of Context-BoF
my $DECAY_SUPER = 0.8;  # d_sup: decay ratio for super-goals
my $DECAY_SUB = 0.8;    # d_sub: decay ratio for sub-goals

#my $graph_uri = "http://collab.open-opinion.org/dsup=$DECAY_SUPER,dsub=$DECAY_SUB,alpha=$WEIGHT_BOW,beta=$WEIGHT_BOT";
my $graph_uri = "http://collab.open-opinion.org";
my $graph_uri_expresult = "http://collab.open-opinion.org/test_b1";

my %term2df = ();
my %term2idf = ();
my %term2idx = ();
my %idx2term = ();

my $num_topic;
my $min_topic_id;
my $bot_vecs = [];
my @p_topics = ();


my $uri2title = ();

if (! @ARGV) {
    print STDERR "Usage: perl calc_similarity.pl [URI of Goal] ...\n";
    exit(0);
}

init_dbh();
init_idf();
init_topics();    
init_mecab();

foreach $goal_uri (@ARGV) {
    print "Goal URI: $goal_uri\n";

    my ($id2val, $context) = build_bof($goal_uri);
    my %goal2sim = get_similar_goals($goal_uri, $id2val, $context);
    my @sorted = sort {$goal2sim{$b} <=> $goal2sim{$a}} (keys(%goal2sim));
    foreach $simgoal (@sorted) {
	my $sim = $goal2sim{$simgoal};
	if ($sim >= $SIM_THRESHOLD) {
	    link_similar_goals($goal_uri, $simgoal, $sim, $this_soft_agent);
	}
    }
}


if ($dbh) {
    $dbh->disconnect();
}

exit(0);


#----------


sub build_bof {
    my $goal_uri = $_[0];

    my %term2freq = ();
    my %id2tf = ();
    my %id2tfidf = ();

    my $sparql = "$SPARQL_PREFIX\n
select ?title ?desc where {
  <$goal_uri> dc:title ?title.
  optional {
    <$goal_uri> dc:description ?desc.
  }
}";

    #print "@@@ $sparql\n";
    my $binding = get_bindings($sparql, $graph_uri)->[0];
    my $title = $binding->{title}->{value};
    utf8::encode($title);
    my $desc = $binding->{desc}->{value};
    utf8::encode($desc);
    

    my $text = "$title。 $desc";
    my %term2freq = get_term2freq($text);
    

    #
    # BagOfWords
    #
    my $sqsum_bow = 0;
    foreach $term (keys(%term2freq)) {
	if ($term =~ /^[ \w:;\/\\\.\{\}\(\)=\|\[\]\*\!\-\'\%\"\#”＆]+$/ || 
	    $term =~ /^\w+\s*=$/ ||
	    length($term) == 0) 
	{
	    next;
	}

	my $tf = $term2freq{$term};
	my $idf = $term2idf{$term};
	if (! $idf) {
	    my $df = 100;
	    $idf = log($N / $df) + 1;
	}
	if ($idf < $IDF_LIMIT) {
	    next;
	}
	
	my $tfidf = sprintf("%.4f", $tf * $idf);
	print "@@@@@@@@@   $term: $tfidf\n";
	
	try {
	    my $query = "SELECT * FROM Features WHERE label='$term';";
	    #print "query: $query\n";
	    my $sth = $dbh->prepare($query);
	    $sth->execute();
	    my $result = $sth->fetchrow_hashref();
	    my $id = $result->{id};
	    $sth->finish();
	    
	    if (length($id) > 0) {
		$id2tfidf{$id} = $tfidf;
		$sqsum_bow += $tfidf * $tfidf;
		$id2tf{$id} = $tf;
		print "$id:$tf\n";
	    }
	} catch {
	    # Fallback to stderr
	    print STDERR "$term\n";
	}
    }
    my @sorted_words = sort {$id2tfidf{$b} <=> $id2tfidf{$a}} (keys(%id2tfidf));
    my $feat_bow = "";
    foreach $id (@sorted_words) {
	my $val = $id2tfidf{$id};
	if ($feat_bow) {
	    $feat_bow .= " ";
	}
	$feat_bow .= "$id:$val";
    }
    my $norm_bow = $sqsum_bow ** 0.5;

    my $query = "DELETE FROM BagOfWords WHERE goal_url='$goal_uri';";
    my $sth = $dbh->prepare($query);
    $sth->execute();
    $sth->finish();

    $query = "INSERT INTO BagOfWords (goal_url,feat,norm) VALUES ('$goal_uri','$feat_bow',$norm_bow);";
    $sth = $dbh->prepare($query);
    $sth->execute();
    $sth->finish();


    #
    # BagOfTopics
    # 
    my $sqsum_bot = 0;
    my $pzd_sum = 0;
    my %id2pzd = ();
    my $feat_bot = "";    
    #print "num_topic: $num_topic\n";

    for (my $topic_i = 0; $topic_i < $num_topic; $topic_i++) {
	my $topic_id = $topic_i + $min_topic_id;
	my $pd = 1;
	foreach $word_id (keys(%id2tf)) {
	    my $tf = $id2tf{$word_id};
	    $pd *= $bot_vecs->[$topic_i]->[$word_id] ** $tf;
	    my $p = $bot_vecs->[$topic_i]->[$word_id];
	    #print "i: $topic_i, word_id: $word_id, tf: $tf, p: $p\n";
	}
	$pzd_sum += $pd * $p_topics[$topic_i];
	$id2pzd{$topic_id} = $pd * $p_topics[$topic_i];
    }
    my @sorted_topic_ids = sort {$id2pzd{$b} <=> $id2pzd{$a}} (keys(%id2pzd));

    foreach $topic_id (@sorted_topic_ids) {
	my $pzd = ($pzd_sum > 0) ? $id2pzd{$topic_id} / $pzd_sum : 0;
	                       # : 1 / $num_topic;
	$pzd = sprintf("%.3f", sprintf("%.3e", $pzd));
	$id2pzd{$topic_id} = $pzd;
	$sqsum_bot += $pzd * $pzd;
	if ($pzd > 0) {
	    if ($feat_bot) {
		$feat_bot .= " ";
	    }
	    $feat_bot .= "$topic_id:$pzd";
	}
    }
    print "feat_bot: $feat_bot\n";
    my $norm_bot = $sqsum_bot ** 0.5;

    $query = "DELETE FROM BagOfTopics WHERE goal_url='$goal_uri';";
    $sth = $dbh->prepare($query);
    $sth->execute();
    $sth->finish();

    $query = "INSERT INTO BagOfTopics (goal_url,feat,norm) VALUES ('$goal_uri','$feat_bot',$norm_bot);";
    $sth = $dbh->prepare($query);
    $sth->execute();
    $sth->finish();

    
    #
    # SelfBagOfFeatures
    #
    my %id2selfval = ();
    my $sqsum_selfbof = 0;

    foreach $id (keys(%id2tfidf)) {
	$id2selfval{$id} = $WEIGHT_BOW * $id2tfidf{$id} / $norm_bow;
	$sqsum_selfbof += $id2selfval{$id} ** 2;
    }
    if ($norm_bot > 0) {
	foreach $id (keys(%id2pzd)) {
	    $id2selfval{$id} = $WEIGHT_BOT * $id2pzd{$id} / $norm_bot;
	    $sqsum_selfbof += $id2selfval{$id} ** 2;
	}
    } else {
	print "Unknown topic: $text\n";
    }
    my $norm_selfbof = $sqsum_selfbof ** 0.5;
    print "norm_selfbof: $norm_selfbof\n";
    my @sorted_self = sort {$id2selfval{$b} <=> $id2selfval{$a}} (keys(%id2selfval));
    my $feat_selfbof = "";

    foreach $id (@sorted_self) {
	my $val = sprintf("%.4f", $id2selfval{$id} / $norm_selfbof);
	$id2selfval{$id} = $val;
	if ($val > 0) {
	    if ($feat_selfbof) {
		$feat_selfbof .= " ";
	    }
	    $feat_selfbof .= "$id:$val";
	}
    }

    print "feat_selfbof: $feat_selfbof\n";

    $query = "DELETE FROM SelfBagOfFeatures WHERE goal_url='$goal_uri';";
    $sth = $dbh->prepare($query);
    $sth->execute();
    $sth->finish();

    $query = "INSERT INTO SelfBagOfFeatures (goal_url,feat) VALUES ('$goal_uri','$feat_selfbof');";
    $sth = $dbh->prepare($query);
    $sth->execute();
    $sth->finish();


    #
    # ContextBagOfFeatures
    #
    my %id2contval = ();
    my $sqsum_contval = 0;
    my %context = get_context($goal_uri);
    for $neighbor (keys(%context)) {
	my $weight_neighbor = $context{$neighbor};
	my $id2neival = get_self_bof($neighbor);
	foreach $id (keys(%id2neival)) {
	    if ($id =~ /\./) {
		print "????? $id\n";
	    }

	    $id2contval{$id} = $weight_neighbor * $id2neival{$id};
	}
    }
    my @sorted_cont = sort {$id2contval{$b} <=> $id2contval{$a}} (keys(%id2contval));
    my $feat_contbof = "";
    foreach $id (@sorted_cont) {
	my $val = sprintf("%.4f", $id2contval{$id});
	$id2contval{$id} = $val;
	if ($val > 0) {
	    $sqsum_contval += $val * $val;
	    if ($feat_contbof) {
		$feat_contbof .= " ";
	    }
	    $feat_contbof .= "$id:$val";
	}
    }
    my $norm_contval = $sqsum_contval ** 0.5;
    print "norm_contval: $norm_contval\n";
    print "feat_contbof: $feat_contbof\n";

    $query = "DELETE FROM ContextBagOfFeatures WHERE goal_url='$goal_uri';";
    $sth = $dbh->prepare($query);
    $sth->execute();
    $sth->finish();

    $query = "INSERT INTO ContextBagOfFeatures (goal_url,feat,norm) VALUES ('$goal_uri','$feat_contbof',$norm_contval);";
    $sth = $dbh->prepare($query);
    $sth->execute();
    $sth->finish();
    

    #
    # BagOfFeatures
    #
    my $weight_context = $WEIGHT_CONTEXT_MAX * tanh($COEF_TANH * $norm_contval);
    my $weight_self = 1 - $weight_context;

    my %id2val = ();
    foreach $id (keys(%id2selfval)) {
	$id2val{$id} += $id2selfval{$id} * $weight_self;
    }
    foreach $id (keys(%id2contval)) {
	$id2val{$id} += $id2contval{$id} * $weight_context;


    }
    my $sqsum_bof = 0;
    foreach $id (keys(%id2val)) {
	$sqsum_bof += $id2val{$id} ** 2;
    }
    my $norm_bof = $sqsum_bof ** 0.5;
    print "norm_bof: $norm_bof\n";

    my @sorted = sort {$id2val{$b} <=> $id2val{$a}} (keys(%id2val));
    my $feat_bof = "";
    foreach $id (@sorted) {
	my $val = sprintf("%.4f", $id2val{$id} / $norm_bof);
	$id2val{$id} = $val;
	if ($val > 0) {
	    if ($feat_bof) {
		$feat_bof .= " ";
	    }
	    $feat_bof .= "$id:$val";
	}
    }    

    print "weight_context: $weight_context\n";
    print "feat_bof: $feat_bof\n";

    $query = "DELETE FROM BagOfFeatures WHERE goal_url='$goal_uri';";
    $sth = $dbh->prepare($query);
    $sth->execute();
    $sth->finish();

    $query = "INSERT INTO BagOfFeatures (goal_url,feat) VALUES ('$goal_uri','$feat_bof');";
    $sth = $dbh->prepare($query);
    $sth->execute();
    $sth->finish();


    #
    # FilterWithFeature
    #
    foreach $id (@sorted) {
	my $val = $id2val{$id};

	if ($val >= $FILTER_THRESHOLD) {
	    my $query = "SELECT goal_urls FROM FilterWithFeature WHERE id=$id;";
	    my $sth = $dbh->prepare($query);
	    $sth->execute();
	    my $result = $sth->fetchrow_hashref();
	    my $goal_urls = $result->{goal_urls};
	    utf8::encode($goal_urls);
	    $sth->finish();
	    
	    if ($goal_urls !~ /$goal_uri/) {
		if ($goal_urls) {
		    $goal_urls .= "\t";
		}
		$goal_urls .= $goal_uri;
		my $query_repl = "REPLACE INTO FilterWithFeature VALUES ($id, '$goal_urls')";

		$sth = $dbh->prepare($query_repl);
		$sth->execute();
		$sth->finish();
	    }
	}	
    }

    return (\%id2val, \%context);
    

}



sub init_mecab {
    $mecab = Text::MeCab->new();
}


sub init_dbh {
    # Open connection
    $dbh = DBI->connect(          
	"dbi:mysql:dbname=$dbname", 
	"$dbUser",
	$dbPassword,                          
	{ RaiseError => 1 ,
	  mysql_enable_utf8 => 1}         
	);
}


sub init_idf {
    my $query = "SELECT df FROM Features WHERE label='TOTAL_DOC_COUNT_N';";
    my $sth = $dbh->prepare($query);
    $sth->execute();
    $N = $sth->fetchrow_hashref()->{df};
    $sth->finish();
    
    
    $query = "SELECT label,df FROM Features WHERE type='Word';";
    $sth = $dbh->prepare($query);
    $sth->execute();
    
    while(my $ref = $sth->fetchrow_arrayref) {
	my ($label,$df) = @$ref;
	utf8::encode($label);
	$term2df{$label} = $df;
	$term2idf{$label} = log($N / $df) + 1;

    }
    $sth->finish();

} 


sub get_term2freq {
    my $text = $_[0];
    my @bases = ();
    my @surfaces = ();
    my @mphs = ();
    my %term2freq = ();
    my $flag = ();
    for (my $n = $mecab->parse($text); $n; $n = $n->next) {
	my $surface = $n->surface;
	my $mph = $n->feature;
	my @mecab_feats = split(/,/, $mph);
	if ($mecab_feats[0] =~ /EOS$/) {
	    next;
	}
	my $base = $mecab_feats[6];

	if ($mph =~ /接尾/) {
	    my $prev = $surfaces[@surfaces-1];
	    my $term = "$prev$base";
	    $term2freq{$term} ++;
	    $flag{$term} = 1;
	} elsif ($mph =~ /(名詞|動詞|形容)/ &&
		 $mph !~ /接頭/ && $me !~ /非自立/ && $mph !~ /助詞/ && 
		 $mph !~ /助動詞/ && $mph !~ /代名詞/ && $mph !~ /名詞,数/ &&
		 length($surface) > 2) {
	    $term2freq{$base}++;
	}
	push(@mphs, $mph);
	push(@bases, $base);
	push(@surfaces, $surface);
    }

    my @ngrams = get_ngrams(\@surfaces, \@mphs);
    foreach $ngram (@ngrams) {
	if (! $flag{$ngram}) {
	    $term2freq{$ngram}++;
	}
    }
    return %term2freq;

}


sub get_ngrams {
    my ($words_ref, $mphs_ref) = @_;
    my @words = @$words_ref;
    my @mphs = @$mphs_ref;
    my @ngrams = ();
    for (my $n = 2; $n <= 2; $n++) {  # for (my $n = 2; $n <= 3; $n++) {
	for (my $i = 0; $i < @words - $n + 1; $i++) {
	    if ($mphs[$i] =~ /(名詞|形容)/ &&
		$mphs[$i] !~ /接尾/ && $mphs[$i] !~ /助詞/ && 
		$mphs[$i] !~ /助動詞/ && $mphs[$i] !~ /非自立/ && 
		$mphs[$i] !~ /名詞,数/ && $mphs[$i+$n-1] !~ /助詞/) {
		my $ngram = join("", @words[$i..$i+$n-1]);
		$ngram =~ s/^\s+//;
		$ngram =~ s/\s+$//;
		if (length($ngram) > 2) {
		    push(@ngrams, $ngram);
		}
	    }
	}
    }
    return @ngrams;
}


sub init_topics {

    my $query = "SELECT id,freq FROM Features WHERE type='Topic';";
    my $sth = $dbh->prepare($query);
    $sth->execute();
    
    my $sum_topics = 0;
    while(my $ref = $sth->fetchrow_arrayref) {
	my ($id,$freq) = @$ref;
	if (! $min_topic_id) {
	    $min_topic_id = $id;
	}
	push(@p_topics, $freq);
	$sum_topics += $freq;
    }
    $sth->finish();
#    print "min_topic_id: $min_topic_id\n";
    for (my $i = 0; $i < @p_topics; $i++) {
	$p_topics[$i] /= $sum_topics;
    }
    

    $query = "SELECT * FROM WordTopicMatrix;";
    $sth = $dbh->prepare($query);
    $sth->execute();

    $num_topic = $sth->{NUM_OF_FIELDS} - 1;
    my $num_word = $sth->rows;

    my %topic_i2sum = ();
    while(my $ref = $sth->fetchrow_arrayref) {
	my $word_id = $ref->[0];
	for (my $k = 1; $k < @$ref; $k++) {
	    my $tf = $ref->[$k];
	    if ($tf == 0) {
		$tf = 0.1;
	    }
	    my $topic_i = $k - 1;
	    #print "topic_i: $topic_i, word_id: $word_id\n";
	    $bot_vecs->[$topic_i]->[$word_id] = $tf;
	    $topic_i2sum{$topic_i} += $tf;
	}
    }
    $sth->finish();

    #print "num_topic: $num_topic, num_word: $num_word\n";
    for (my $topic_i = 0; $topic_i < $num_topic; $topic_i++) {
	for (my $word_id = 0; $word_id < $num_word; $word_id++) {
	    #print "topic_i2sum{$topic_i}: $topic_i2sum{$topic_i}\n"; 
	    $bot_vecs->[$topic_i]->[$word_id] /= $topic_i2sum{$topic_i};
	    #print "topic_i: $topic_i, word_id: $word_id, val: $bot_vecs->[$topic_i]->[$word_id]\n";
	}

    }

}


sub get_self_bof {
    my $goal_uri = $_[0];
    try {
	my $query = "SELECT feat FROM SelfBagOfFeatures WHERE goal_url='$goal_uri';";
	my $sth = $dbh->prepare($query);
	$sth->execute();
	my $result = $sth->fetchrow_hashref();
	$sth->finish();
	my $feat = $result->{feat};
	#print "goal_uri: $goal_uri\n";
	#print "  feat: $feat\n";
	return feat2bof($feat);
    } catch {
	# Fallback to stderr
	print STDERR "$term\n";
    }

}


sub feat2bof {
    my $feat = $_[0];
    my @tokens = split(/\s+/, $feat);
    my %bof = ();
    foreach $token (@tokens) {
	if ($token =~ /^([0-9]+):([\d\.eE\-\+]+)$/) {
	    my $id = $1;
	    my $val = $2;
	    $bof{$id} = $val;
	}
    }
    return %bof;
}


sub get_context {
    my $goal_uri = $_[0];
    my $sparql = $SPARQL_PREFIX .
        "select ?title { <$goal_uri> dc:title ?title.}";
    my $bindings = get_bindings($sparql, $graph_uri);
    my $title = $bindings->[0]->{"title"}->{"value"};
    utf8::encode($title);
    #print "++++title: $title\n";

    my %ancestors = get_ancestor_goals($goal_uri, 1, {$goal_uri=>1});
    my $decendants = get_decendant_goals($goal_uri, 1, {$goal_uri=>1});
    return (%ancestors, %descendants);
}


sub get_ancestor_goals {
    my ($goal_uri, $weight, $ref) = @_;
    my %flag = ();
    my %goal2weight = ();
    do {
	my @supergoals = get_supergoals($goal_uri);
	foreach $supergoal (@supergoals) {
	    if ($ref->{$supergoal}) {
		next;
	    }
	    $ref->{$supergoal} = 1;
	    print "@@@ [supergoal] $supergoal\n";
	    my $super_title = $uri2title{$supergoal};
	    print "super_title: $super_title\n";
	    #$supergoal = encode("utf-8", $supergoal);	    
	    $goal2weight{$supergoal} = $weight * $DECAY_SUPER;
	    %goal2weight = (%goal2weight, get_ancestor_goals($supergoal, $weight * $DECAY_SUPER, $ref));
	}
    } while (@supergoals);
    return %goal2weight;
}

sub get_supergoals {
    my $goal_uri = $_[0];
    if (! $goal_uri) {
	return ();
    }
    
    my $sparql = $SPARQL_PREFIX .
      "select distinct ?supergoal ?title where {\n
       ?supergoal socia:subGoal <$goal_uri>;\n 
       dc:title ?title.}";
    #print "[SPARQL] $sparql\n\n";
    my $bindings = get_bindings($sparql, $graph_uri);
    my %flag = ();
    foreach $binding (@$bindings) {
	my $supergoal = $binding->{"supergoal"}->{"value"};
	if ($supergoal) {
	    $flag{$supergoal} = 1;
	    $uri2title{$supergoal} = $binding->{"title"}->{"value"};
	    utf8::encode($uri2title{$supergoal});
	}
    }
    return keys(%flag);
}


sub get_decendant_goals {
    my ($goal_uri, $weight, $ref) = @_;
    my %flag = ();
    my %goal2weight = ();
    do {
	my @subgoals = get_subgoals($goal_uri);
	foreach $subgoal (@subgoals) {
	    if ($ref->{$subgoal}) {
		next;
	    }
	    $ref->{$subgoal} = 1;
	    print "@@@ [subgoal] $subgoal\n";
	    my $sub_title = $uri2title{$subgoal};
	    print "sub_title: $sub_title\n";
	    #$subgoal = encode("utf-8", $subgoal);
	    $goal2weight{$subgoal} = $weight * $DECAY_SUB;
	    %goal2weight = (%goal2weight, get_decendant_goals($subgoal, $weight * $DECAY_SUB, $ref));
	}
    } while (@subgoals);
    return %goal2weight;
}


sub get_subgoals {
    my $goal_uri = $_[0];
    if (! $goal_uri) {
	return ();
    }
    
    my $sparql = $SPARQL_PREFIX .
      "select distinct ?subgoal ?title where {\n
       <$goal_uri> socia:subGoal ?subgoal.\n
       ?subgoal dc:title ?title.}";
    #print "[SPARQL] $sparql\n\n";
    my $bindings = get_bindings($sparql, $graph_uri);
    my %flag = ();
    foreach $binding (@$bindings) {
	my $subgoal = $binding->{"subgoal"}->{"value"};
	if ($subgoal) {
	    $flag{$subgoal} = 1;
	    $uri2title{$subgoal} = $binding->{"title"}->{"value"};
	    utf8::encode($uri2title{$subgoal});
	}
    }
    return keys(%flag);
}


sub get_similar_goals {
    my ($goal_uri, $ref_id2val, $ref_context) = @_;
    my %id2val = %$ref_id2val;
    my %context = %$ref_context;
    my $decoded = $goal_uri;
    utf8::decode($decoded);
    $context{$decoded} = 1;

    my %goal2sim = ();

    my $condition = "";
    foreach $id (keys(%id2val)) {
	if ($condition) {
	    $condition .= " || ";
	}
	$condition .= "id=$id";
    }
    #print "condition: $condition\n";

    my $query = "SELECT goal_urls FROM FilterWithFeature WHERE $condition;";
    my $sth = $dbh->prepare($query);
    $sth->execute();
    
    my $sum_topics = 0;
    while(my $ref = $sth->fetchrow_arrayref) {
	my @goal_urls = split(/\t/, $ref->[0]);
	foreach $goal (@goal_urls) {
	    #utf8::encode($goal);
	    if ($goal2sim{$goal}) {
		next;
	    }

	    print "goal pair: $goa_uri, $goal\n";
	    print "    [context!!] $goal, $context{$goal}\n";

	    #print "!!!!!!!! candidate of simgoal: $goal\n";
	    if (! $context{$goal}) {
		print "NOT FILTERED OUT!!!!\n";

		my $query_bof = "SELECT feat FROM BagOfFeatures WHERE goal_url='$goal'";
		my $sth_bof = $dbh->prepare($query_bof);
		$sth_bof->execute();
		my $result = $sth_bof->fetchrow_hashref();
		my $feat = $result->{feat};
		$sth_bof->finish();

		my %id2simval = feat2bof($feat);
		#print "!!!! feat: $feat\n";

		my $sim = cossim(\%id2val, \%id2simval);
		#print "sim: $sim\n";
		if ($sim) {
		    $goal2sim{$goal} = $sim;
		}
	    }
	}
    }
    $sth->finish();

    return %goal2sim;
}

sub link_similar_goals {
    my ($goal1_uri, $goal2_uri, $similarity, $annotator) = @_;

    print "goal1: $goal1_uri, goal2: $goal2_uri, sim: $similarity, annotator: $annotator\n";

    my $n3_link = "<$goal1_uri> schema:isSimilarTo <$goal2_uri>.\n
<$goal2_uri> schema:isSimilarTo <$goal1_uri>.";

    #print "$n3_link\n\n";

    #my $result_link = insert_n3($n3_link, $graph_uri);
    my $result_link = insert_n3($n3_link, $graph_uri_expresult);
    #print "result_link: $result_link\n\n";

    my $result_del1 = delete_where("?ai a socia:AnnotationInfo; socia:property schema:isSimilarTo; socia:source <$goal1_uri>; socia:target <$goal2_uri>; ?p ?o.", 
				   "?ai ?p ?o.", $graph_uri_expresult);
    my $n3_aninfo1 = create_n3_aninfo($goal1_uri, $goal2_uri, $similarity, $annotator);
    #my $result_aninfo1 = insert_n3($n3_aninfo1, $graph_uri);
    my $result_aninfo1 = insert_n3($n3_aninfo1, $graph_uri_expresult);
    #print "result_aninfo1: $result_aninfo1\n\n";

    my $reuslt_del2 = delete_where("?ai a socia:AnnotationInfo; socia:property schema:isSimilarTo; socia:source <$goal2_uri>; socia:target <$goal1_uri>; ?p ?o.",
				   "?ai ?p ?o.", $graph_uri_expresult);
    my $n3_aninfo2 = create_n3_aninfo($goal2_uri, $goal1_uri, $similarity, $annotator);
    #my $result_aninfo2 = insert_n3($n3_aninfo2, $graph_uri);
    my $result_aninfo2 = insert_n3($n3_aninfo2, $graph_uri_expresult);

    my $result_json = "{\"result\":\"ok\"}";
    print $result_json;
}


sub insert_n3 {
    my ($n3, $graph_uri) = @_;
    my $sparql = "${SPARQL_PREFIX}\n".
	"INSERT DATA INTO <$graph_uri> {$n3}";
    return execute_sparul($sparql);
}

sub delete_where {
    my ($pattern, $n3_del, $g_uri) = @_;
    my $sparul = "${SPARQL_PREFIX}\n".
	"WITH <$g_uri>\nDELETE { $n3_del }\n".
	"WHERE { $pattern }";
    #print "$sparul\n";
    return execute_sparul($sparul);
}


sub create_n3_aninfo {
    my ($goal1_uri, $goal2_uri, $similarity, $annotator) = @_;
    my $millisec = get_millisec();
    print "millisec: $millisec\n";
    my $date_time = current_date_time();
    my $aninfo1_uri = "http://collab.open-opinion.org/resource/aninfo${millisec}_1"; 
    my $aninfo2_uri = "http://collab.open-opinion.org/resource/aninfo${millisec}_2";
    
    my $n3_aninfo = "<$aninfo1_uri> rdf:type <$aninfo_class>;\n
      socia:source <$goal1_uri>;\n
      socia:target <$goal2_uri>;\n
      socia:property schema:isSimilarTo;\n
      dc:created \"$date_time\"^^xsd:dateTime;\n
      socia:annotator <$annotator>;\n
      socia:weight \"$similarity\"^^xsd:float.\n\n

      <$aninfo2_uri> rdf:type <$aninfo_class>;\n
      socia:source <$goal2_uri>;\n
      socia:target <$goal1_uri>;\n
      socia:property schema:isSimilarTo;\n
      dc:created \"$date_time\"^^xsd:dateTime;\n
      socia:annotator <$annotator>;\n
      socia:weight \"$similarity\"^^xsd:float.\n";
    
    return $n3_aninfo;
}

sub current_date_time {
    my $tzhere = DateTime::TimeZone->new( name => "Asia/Tokyo" );
    my $dt = DateTime->now(time_zone => $tzhere);
    return $dt->strftime('%Y-%m-%dT%H:%M:%S+09:00');
}

sub get_millisec {
    my ($sec,$microsec) = gettimeofday();
    my $millisec = $sec * 1000 + int($microsec / 1000);
    return $millisec;
}


sub cossim {
    my ($vec1, $vec2) = @_;
    my $x_sqsum = 0, $y_sqsum = 0, $prod_sum = 0;
    foreach $key (keys(%$vec1)) {
	my $x = $vec1->{$key};
	my $y = $vec2->{$key};
	$x_sqsum += $x * $x;
	$prod_sum += $x * $y;
    }
    foreach $key (keys(%$vec2)) { 
	my $y = $vec2->{$key};
	$y_sqsum += $y * $y;
    }
    my $denomi = ($y_sqsum ** 0.5) * ($x_sqsum ** 0.5);
    if ($denomi > 0) {
	return $prod_sum / $denomi;
    } else {
	return 0;
    }
}
