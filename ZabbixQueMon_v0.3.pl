#!/usr/bin/perl
#
# 
# *** SVFE Queue Monitoring for Zabbix ****
#
# Purpose: 
#  Print in shell JSON-like list of dictionaries, informing about current state of Linux queues
#  In use by Zabbix monitoring system. The script runs by Zabbix agent in endless cycle for online queue tracking
#  The queue data will be printed one time after each script launch, then the script will finish the work
#  It doesn't repeat the checking by itself, so, if you need multiple checking you have to run the script many times
# 
#  
#
# Output example:
#  [
#   
#
#  ]
#
# Script info:
#  Version v0.3
#  Author Fedor Ivanov | Unlimint
#  Released in Nov 2022 
#
# Requirements: 
#  Perl 5; (!) Not compatible with Perl 6;
#  Linux server with available shell commands: ipcs, awk, grep, ps; 
#  Running SVFE on the server;
# 
# Additional:
#  Was 
#  Has been tested on Linux Centos only
#
# use perl || die;
#

use strict;
use warnings;
use 5.010;

use constant {
    # Plain constant PROCESS_DOWN
    PROCESS_IS_DOWN => q(PROCESS_DOWN),
    
    # Final Output template. Output has to be returned as a JSON-like list of dictionaries
    TEMPLATE_OUTPUT => qq([\n%s\n]),

    # Template for each string in the Result
    TEMPLATE_STRING => qq(\n  {\n    "process_name": "%s",\n    "message": %d\n  }),

    # Command to get all current Linux Queues. Returns space-separated representation "<que_id> <messages_count>\n<another_que_id> <messages_count>" etc
    COMMAND_GET_QUE => q(ipcs -q | awk '{print $2" "$6}' | grep -vi message),

    # Command to get the Receiver PID of a specific Queue. If the process was found returns exactly one number - Linux Process ID
    COMMAND_GET_PID => q(ipcs -p | grep %s | awk '{print $NF}'),
    
    # Command to get the Process name of specific PID. Returns string with process name like tcpcomms, epayint etc
    COMMAND_GET_TAG => q(ps -ef | grep -v grep | awk '{print $2" "$8}' | grep %s | awk '{print $NF}'),
};

sub main { 

    #
    # Input: No
    # Output: No
    #
    # General high-level function for running the main scenario 
    # The function has no input and output and doesn't perform any data processing by itself, manages other functions instead 
    #
    
    my %queues = get_queues_dict();
    my $output = get_output_data(%queues);
    
    say $output;
}

sub get_queues_dict {

    #
    # Input: No
    # Output: %hash {"process_name": <some_receiver_process>, "messages": <count_of_messages_in_queue>, ...}
    #
    # Returns hash, containing current state of Queues using template {"process_name": <some_receiver_process>, "messages": <count_of_messages_in_queue>}
    # When SVFE runs a few same processes in parallel - the messages count will be summarized using the process name
    # When the Receiver process is down the process name will be substituted by PROCESS_IS_DOWN constant
    #
    
    my %queues = ();
    my ($qid, $messages, $process_id, $process_name) = '';
    my @queues_set = split "\n", execute_command(COMMAND_GET_QUE);

    for(@queues_set) {
        next if /^\D/; # Proceed to the next iteration if the line doesn't start from numbers (no queue id recognized)
        ($qid, $messages) = split;
        $process_id = execute_command(COMMAND_GET_PID, $qid);
        next if not $process_id; # Proceed to the next iteration if the Process ID wasn't found using the Linux "ps" command
        $process_name = execute_command(COMMAND_GET_TAG, $process_id);
        $process_name =~  s/\s+//g;
        $process_name = PROCESS_IS_DOWN if not $process_name;
        $queues{$process_name} = 0 if not $queues{$process_name};
        $queues{$process_name} += $messages;
    }

    return %queues;
}

sub get_output_data { 

    #
    # Input: %hash {"process_name": <some_receiver_process>, "messages": <count_of_messages_in_queue>, ...}
    # Output: $string, ready to print without any changes
    #
    # Calculates and returns formatted final output string
    # No changes should be made to the result of the function, the result fully ready to be printed
    # When no running queues were found in the system the function will return an empty result using TEMPLATE_OUTPUT
    #
    
    my $output;
    my @body = ();
    my %queues = @_;

    while ((my $process_name, $messages_count) = each %queues) {  # Split the incoming %hash to key => value pairs
        my $output_string = sprintf TEMPLATE_STRING, $process_name, $messages_count;
        push(@body, $output_string);
    }
    
    $output = join(',', @body);  # $output becomes a blank string if @body has no elements
    $output = sprintf TEMPLATE_OUTPUT, $output;  # When @body has no elements empty JSON-like [list] will be returned
    
    return $output;
}

sub execute_command {

    #
    # Input: @list of $strings, the first element is the command template, the others - are command params to be merged with the template
    # Output: $string, the command execution result
    #
    # Runs ssh commands using incoming command template and params
    # When the command has no external params the Params can be absent, the command will be run as is
    # For the merge of the Params with the Command template the sprintf function will be used 
    #
    
    my ($command_template, @params) = @_;
    my $command = @params ? sprintf $command_template, @params : $command_template;
    
    chomp(my $result = qx($command)); # Execute the assembled command

    return $result;
}

main(); # Entry point, the script work begin here
