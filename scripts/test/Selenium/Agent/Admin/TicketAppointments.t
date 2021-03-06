# --
# Copyright (C) 2001-2018 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;
use utf8;

use vars (qw($Self));

my $Selenium = $Kernel::OM->Get('Kernel::System::UnitTest::Selenium');

$Selenium->RunTest(
    sub {

        my $Helper                  = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
        my $ConfigObject            = $Kernel::OM->Get('Kernel::Config');
        my $GroupObject             = $Kernel::OM->Get('Kernel::System::Group');
        my $DynamicFieldObject      = $Kernel::OM->Get('Kernel::System::DynamicField');
        my $DynamicFieldValueObject = $Kernel::OM->Get('Kernel::System::DynamicFieldValue');
        my $TicketObject            = $Kernel::OM->Get('Kernel::System::Ticket');
        my $ArticleBackendObject    = $Kernel::OM->Get('Kernel::System::Ticket::Article')->BackendForChannel(
            ChannelName => 'Email',
        );

        my $RandomID = $Helper->GetRandomID();

        # Create test group.
        my $GroupName = "Calendar-group-$RandomID";
        my $GroupID   = $GroupObject->GroupAdd(
            Name    => $GroupName,
            ValidID => 1,
            UserID  => 1,
        );
        $Self->True(
            $GroupID,
            'Test group created',
        );

        # Create test queue with escalation rules.
        my $QueueID = $Kernel::OM->Get('Kernel::System::Queue')->QueueAdd(
            Name                => "Queue$RandomID",
            ValidID             => 1,
            GroupID             => $GroupID,
            FirstResponseTime   => 30,
            FirstResponseNotify => 70,
            UpdateTime          => 240,
            UpdateNotify        => 80,
            SolutionTime        => 2440,
            SolutionNotify      => 90,
            SystemAddressID     => 1,
            SalutationID        => 1,
            SignatureID         => 1,
            Comment             => 'Some comment',
            UserID              => 1,
        );
        $Self->True(
            $QueueID,
            'Test queue created',
        );

        # Create test dynamic fields.
        my @DynamicFields = (
            {
                Name       => 'Date' . $RandomID,
                Label      => 'Date' . $RandomID,
                Config     => {},
                FieldOrder => 10000,
                FieldType  => 'Date',
                ObjectType => 'Ticket',
                ValidID    => 1,
                UserID     => 1,
            },
            {
                Name       => 'DateTime' . $RandomID,
                Label      => 'DateTime' . $RandomID,
                Config     => {},
                FieldOrder => 10000,
                FieldType  => 'DateTime',
                ObjectType => 'Ticket',
                ValidID    => 1,
                UserID     => 1,
            },
        );
        for my $DynamicField (@DynamicFields) {
            my $DynamicFieldID = $DynamicFieldObject->DynamicFieldAdd(
                %{$DynamicField},
            );
            $Self->True(
                $DynamicFieldID,
                "DynamicFieldAdd - $DynamicField->{Name} ($DynamicFieldID)",
            );
            $DynamicField->{DynamicFieldID} = $DynamicFieldID;
        }

        my $SchedulerDBObject = $Kernel::OM->Get('Kernel::System::Daemon::SchedulerDB');

        # Remove scheduled tasks from DB, as they may interfere with tests run later.
        my @AllTasks = $SchedulerDBObject->TaskList();
        for my $Task (@AllTasks) {
            my $Success = $SchedulerDBObject->TaskDelete(
                TaskID => $Task->{TaskID},
            );
            $Self->True(
                $Success,
                "TaskDelete - Removed scheduled task $Task->{TaskID}",
            );
        }

        my $Home           = $ConfigObject->Get('Home');
        my $Daemon         = $Home . '/bin/otrs.Daemon.pl';
        my $DaemonExitCode = 1;

        # Get current daemon status.
        my $PreviousDaemonStatus = `$Daemon status`;

        # Daemon already running, do nothing.
        if ( $PreviousDaemonStatus =~ m{Daemon running}i ) {
            $Self->True(
                1,
                'Daemon already running'
            );
        }

        # Daemon is not running, start it.
        else {
            $DaemonExitCode = system("$Daemon start > /dev/null");
            $Self->False(
                $DaemonExitCode,
                'Daemon started successfully'
            );
        }

        # Freeze time at this point since creating appointments and tickets and checking results can
        #   take some time to complete.
        $Helper->FixedTimeSet();

        # Create a test ticket.
        my $TicketTitle = "Ticket$RandomID";
        my $TicketID    = $TicketObject->TicketCreate(
            Title        => $TicketTitle,
            QueueID      => $QueueID,
            Lock         => 'unlock',
            Priority     => '3 normal',
            State        => 'open',
            CustomerID   => 'customer-a@example.com',
            CustomerUser => 'customer-a@example.com',
            OwnerID      => 1,
            UserID       => 1,
        );
        $Self->True(
            $TicketID,
            "TicketCreate() - $TicketTitle ($TicketID)",
        );

        # Create email article.
        my $ArticleID = $ArticleBackendObject->ArticleCreate(
            TicketID             => $TicketID,
            SenderType           => 'customer',
            IsVisibleForCustomer => 1,
            From                 => 'Some Customer A <customer-a@example.com>',
            To                   => 'Some Agent <email@example.com>',
            Subject              => 'some short description',
            Body                 => 'the message text',
            ContentType          => 'text/plain; charset=ISO-8859-15',
            HistoryType          => 'EmailCustomer',
            HistoryComment       => 'Customer sent an email',
            UserID               => 1,
        );

        # Build escalation index.
        my $Success = $TicketObject->TicketEscalationIndexBuild(
            TicketID => $TicketID,
            UserID   => 1,
        );
        $Self->True(
            $Success,
            'TicketEscalationIndexBuild',
        );

        # Get escalation times.
        my %EscalationTimes;
        my %Ticket = $TicketObject->TicketGet(
            TicketID => $TicketID,
            UserID   => 1,
        );

        for my $EscalationType (qw(FirstResponseTime UpdateTime SolutionTime)) {
            my $EscalationTimeStartObject = $Kernel::OM->Create(
                'Kernel::System::DateTime',
                ObjectParams => {
                    String => $Ticket{ $EscalationType . 'DestinationDate' },
                },
            );
            $EscalationTimes{ $EscalationType . 'Start' } = $EscalationTimeStartObject->ToString();

            # Different escalation types have different end time rules (see below in tests).
            my $Minutes = 0;
            if ( $EscalationType eq 'FirstResponseTime' ) {
                $Minutes = 5;    # Plus_5
            }
            elsif ( $EscalationType eq 'UpdateTime' ) {
                $Minutes = 15;    # Plus_15
            }
            elsif ( $EscalationType eq 'SolutionTime' ) {
                $Minutes = 30;    # Plus_30
            }

            my $EscalationTimeEndObject = $EscalationTimeStartObject->Clone();
            $EscalationTimeEndObject->Add(
                Minutes => $Minutes,
            );
            $EscalationTimes{ $EscalationType . 'End' } = $EscalationTimeEndObject->ToString();
        }

        # Set pending time to next day.
        my $DateTimeObject         = $Kernel::OM->Create('Kernel::System::DateTime');
        my $PendingTimeStartObject = $DateTimeObject->Clone();
        $PendingTimeStartObject->Set(
            Second => 0,
        );
        $PendingTimeStartObject->Add(
            Days => 1,
        );

        $Success = $TicketObject->TicketPendingTimeSet(
            %{ $PendingTimeStartObject->Get() },
            TicketID => $TicketID,
            UserID   => 1,
        );
        $Self->True(
            $Success,
            "TicketPendingTimeSet - Ticket $TicketID: " . $PendingTimeStartObject->ToString()
        );

        # Calculate pending end time.
        my $PendingTimeEndObject = $PendingTimeStartObject->Clone();
        $PendingTimeEndObject->Add(
            Hours => 1,
        );

        # Calculate expected UntilTime.
        my $UntilDateTimeObject = $Kernel::OM->Create(
            'Kernel::System::DateTime',
            ObjectParams => {
                String => '2016-01-01 00:00:00',
            },
        );
        my $UntilTimeDelta = $Kernel::OM->Create('Kernel::System::DateTime')->Delta(
            DateTimeObject => $UntilDateTimeObject,
        );
        my $UntilTime = -$UntilTimeDelta->{AbsoluteSeconds};

        # Set dynamic field values.
        my $DynamicField1TimeObject = $Kernel::OM->Create(
            'Kernel::System::DateTime',
            ObjectParams => {
                String => '2016-01-01 00:00:00',
            },
        );
        $Success = $DynamicFieldValueObject->ValueSet(
            FieldID  => $DynamicFields[0]->{DynamicFieldID},
            ObjectID => $TicketID,
            Value    => [
                {
                    ValueDateTime => $DynamicField1TimeObject->ToString(),
                },
            ],
            UserID => 1,
        );
        $Self->True(
            $Success,
            "ValueSet - $DynamicFields[0]->{DynamicFieldID} for ticket $TicketID",
        );

        my $DynamicField2TimeObject = $Kernel::OM->Create(
            'Kernel::System::DateTime',
            ObjectParams => {
                String => '2016-01-01 12:00:00',
            },
        );
        $Success = $DynamicFieldValueObject->ValueSet(
            FieldID  => $DynamicFields[1]->{DynamicFieldID},
            ObjectID => $TicketID,
            Value    => [
                {
                    ValueDateTime => $DynamicField2TimeObject->ToString(),
                },
            ],
            UserID => 1,
        );
        $Self->True(
            $Success,
            "ValueSet - $DynamicFields[1]->{DynamicFieldID} for ticket $TicketID",
        );

        my $ScriptAlias = $ConfigObject->Get('ScriptAlias');

        # Change resolution (desktop mode).
        $Selenium->set_window_size( 768, 1050 );

        # Create test user.
        my $Language      = 'en';
        my $TestUserLogin = $Helper->TestUserCreate(
            Groups   => [ 'admin', $GroupName ],
            Language => $Language,
        ) || die 'Did not get test user';

        $Selenium->Login(
            Type     => 'Agent',
            User     => $TestUserLogin,
            Password => $TestUserLogin,
        );

        # Open AdminAppointmentCalendarManage page.
        $Selenium->VerifiedGet("${ScriptAlias}index.pl?Action=AdminAppointmentCalendarManage");

        # Add new calendar.
        my $CalendarName = "Calendar $RandomID";
        $Selenium->find_element( '.SidebarColumn ul.ActionList a#Add',   'css' )->VerifiedClick();
        $Selenium->find_element( 'form#CalendarFrom input#CalendarName', 'css' )->send_keys($CalendarName);
        $Selenium->execute_script(
            "\$('#GroupID').val($GroupID).trigger('redraw.InputField').trigger('change');"
        );

        $Selenium->find_element( 'form#CalendarFrom button#Submit', 'css' )->VerifiedClick();

        # Get calendar ID.
        my %Calendar = $Kernel::OM->Get('Kernel::System::Calendar')->CalendarGet(
            CalendarName => $CalendarName,
        );
        $Self->True(
            $Calendar{CalendarID},
            "CalendarGet - Found calendar $Calendar{CalendarID}",
        );

        # Go to calendar edit page.
        $Selenium->VerifiedGet(
            "${ScriptAlias}index.pl?Action=AdminAppointmentCalendarManage;Subaction=Edit;CalendarID=$Calendar{CalendarID}"
        );

        my $AppointmentObject = $Kernel::OM->Get('Kernel::System::Calendar::Appointment');
        my $CacheObject       = $Kernel::OM->Get('Kernel::System::Cache');

        # Sleep for slow systems.
        my $SleepTime = 2;

        #
        # Tests for ticket appointments
        #
        my @Tests = (
            {
                Name   => 'FirstResponseTime',
                Config => {
                    StartDate    => 'FirstResponseTime',
                    EndDate      => 'Plus_5',
                    QueueID      => $QueueID,
                    SearchParams => {
                        Title => $TicketTitle,
                    },
                },
                Result => {
                    Title => sprintf(
                        "[%s%s%s] %s",
                        $ConfigObject->Get('Ticket::Hook'),
                        $ConfigObject->Get('Ticket::HookDivider'),
                        $Ticket{TicketNumber},
                        $TicketTitle
                    ),
                    StartTime => $EscalationTimes{FirstResponseTimeStart},
                    EndTime   => $EscalationTimes{FirstResponseTimeEnd},
                },
            },
            {
                Name   => 'UpdateTime',
                Config => {
                    StartDate    => 'UpdateTime',
                    EndDate      => 'Plus_15',
                    QueueID      => $QueueID,
                    SearchParams => {
                        Title => $TicketTitle,
                    },
                },
                Result => {
                    Title => sprintf(
                        "[%s%s%s] %s",
                        $ConfigObject->Get('Ticket::Hook'),
                        $ConfigObject->Get('Ticket::HookDivider'),
                        $Ticket{TicketNumber},
                        $TicketTitle
                    ),
                    StartTime => $EscalationTimes{UpdateTimeStart},
                    EndTime   => $EscalationTimes{UpdateTimeEnd},
                },
            },
            {
                Name   => 'SolutionTime',
                Config => {
                    StartDate    => 'SolutionTime',
                    EndDate      => 'Plus_30',
                    QueueID      => $QueueID,
                    SearchParams => {
                        Title => $TicketTitle,
                    },
                },
                Result => {
                    Title => sprintf(
                        "[%s%s%s] %s",
                        $ConfigObject->Get('Ticket::Hook'),
                        $ConfigObject->Get('Ticket::HookDivider'),
                        $Ticket{TicketNumber},
                        $TicketTitle
                    ),
                    StartTime => $EscalationTimes{SolutionTimeStart},
                    EndTime   => $EscalationTimes{SolutionTimeEnd},
                },
            },
            {
                Name   => 'DynamicField',
                Config => {
                    StartDate    => 'DynamicField_' . $DynamicFields[0]->{Name},
                    EndDate      => 'DynamicField_' . $DynamicFields[1]->{Name},
                    QueueID      => $QueueID,
                    SearchParams => {
                        Title => $TicketTitle,
                    },
                },
                Result => {
                    Title => sprintf(
                        "[%s%s%s] %s",
                        $ConfigObject->Get('Ticket::Hook'),
                        $ConfigObject->Get('Ticket::HookDivider'),
                        $Ticket{TicketNumber},
                        $TicketTitle
                    ),
                    StartTime => $DynamicField1TimeObject->ToString(),
                    EndTime   => $DynamicField2TimeObject->ToString(),
                },
                Update => {
                    StartTime => '1953-06-28 10:20:00',
                    EndTime   => '2016-07-04 19:45:00',
                },
                UpdateResult => {
                    'DynamicField_' . $DynamicFields[0]->{Name} => '1953-06-28 10:20:00',
                    'DynamicField_' . $DynamicFields[1]->{Name} => '2016-07-04 19:45:00',
                },
            },
            {
                Name   => 'PendingTime',
                Config => {
                    StartDate    => 'PendingTime',
                    EndDate      => 'Plus_60',
                    QueueID      => $QueueID,
                    SearchParams => {
                        Title => $TicketTitle,
                    },
                },
                Result => {
                    Title => sprintf(
                        "[%s%s%s] %s",
                        $ConfigObject->Get('Ticket::Hook'),
                        $ConfigObject->Get('Ticket::HookDivider'),
                        $Ticket{TicketNumber},
                        $TicketTitle
                    ),
                    StartTime => $PendingTimeStartObject->ToString(),
                    EndTime   => $PendingTimeEndObject->ToString(),
                },
                Update => {
                    StartTime => '2016-01-01 00:00:00',
                    EndTime   => '2016-01-01 01:00:00',
                },
                UpdateResult => {
                    UntilTime => $UntilTime,
                },
            },
        );

        for my $Test (@Tests) {

            # Add ticket appointment rule.
            $Selenium->find_element( '.WidgetSimple.Collapsed .WidgetAction.Toggle a', 'css' )->VerifiedClick();
            $Selenium->find_element( '#AddRuleButton',                                 'css' )->VerifiedClick();

            # Set start date module.
            if ( $Test->{Config}->{StartDate} ) {
                $Selenium->execute_script(
                    "\$('#StartDate_1').val('$Test->{Config}->{StartDate}').trigger('redraw.InputField').trigger('change');"
                );
            }

            # Set end date module.
            if ( $Test->{Config}->{EndDate} ) {
                $Selenium->execute_script(
                    "\$('#EndDate_1').val('$Test->{Config}->{EndDate}').trigger('redraw.InputField').trigger('change');"
                );
            }

            # Set a queue.
            if ( $Test->{Config}->{QueueID} ) {
                $Selenium->execute_script(
                    "\$('#QueueID_1').val('$Test->{Config}->{QueueID}').trigger('redraw.InputField').trigger('change');"
                );
            }

            # Add ticket search parameters.
            if ( $Test->{Config}->{SearchParams} ) {
                for my $SearchParam ( sort keys %{ $Test->{Config}->{SearchParams} || {} } ) {
                    $Selenium->execute_script(
                        "\$('#SearchParams').val('$SearchParam').trigger('redraw.InputField').trigger('change');"
                    );
                    $Selenium->find_element( '.AddButton',                  'css' )->VerifiedClick();
                    $Selenium->find_element( "#SearchParam_1_$SearchParam", 'css' )
                        ->send_keys( $Test->{Config}->{SearchParams}->{$SearchParam} );
                }
            }

            $Selenium->find_element( 'form#CalendarFrom button#SubmitAndContinue', 'css' )->VerifiedClick();
            $Self->True(
                1,
                "$Test->{Name} - Added ticket appointment rule",
            );

            # Wait for daemon to do its magic.
            print "Waiting at most $SleepTime s until tasks are executed\n";
            ACTIVESLEEP:
            for my $Seconds ( 1 .. $SleepTime ) {
                my @List = $SchedulerDBObject->TaskList();
                last ACTIVESLEEP if !scalar @List;
                print "Sleeping for $Seconds seconds...\n";
                sleep 1;
            }

            # Make sure the cache is correct.
            $CacheObject->CleanUp(
                Type => "AppointmentList$Calendar{CalendarID}",
            );

            # Get list of existing appointments in the calendar.
            my @Appointments = $AppointmentObject->AppointmentList(
                CalendarID => $Calendar{CalendarID},
            );
            $Self->Is(
                scalar @Appointments,
                1,
                "$Test->{Name} - Ticket appointment found"
            );
            my $Appointment = $Appointments[0];

            # Check appointment data.
            for my $Field ( sort keys %{ $Test->{Result} || {} } ) {
                $Self->Is(
                    substr( $Appointment->{$Field},    0, -3 ),
                    substr( $Test->{Result}->{$Field}, 0, -3 ),
                    "$Test->{Name} - Appointment field $Field"
                );
            }

            # Update appointment data.
            if ( $Test->{Update} && $Test->{UpdateResult} ) {
                my $Success = $AppointmentObject->AppointmentUpdate(
                    %{$Appointment},
                    %{ $Test->{Update} },
                    UserID => 1,
                );
                $Self->True(
                    $Success,
                    "$Test->{Name} - Appointment updated"
                );

                # Wait for daemon to do its magic.
                sleep $SleepTime;

                # Make sure the cache is correct.
                $CacheObject->CleanUp(
                    Type => 'Ticket',
                );

                # Check ticket data.
                %Ticket = $TicketObject->TicketGet(
                    TicketID      => $TicketID,
                    DynamicFields => 1,
                    UserID        => 1,
                );
                FIELD:
                for my $Field ( sort keys %{ $Test->{UpdateResult} || {} } ) {

                    # In case of UntilTime, it can happen that there is an error of one second overall. This is
                    #   acceptable, so in this case calculate the difference and allow for this error.
                    if ( $Field eq 'UntilTime' ) {
                        $Self->True(
                            abs( $Test->{UpdateResult}->{UntilTime} - $Ticket{UntilTime} ) < 2,
                            $Test->{UpdateResult}->{$Field},
                            "$Test->{Name} - Ticket field UntilTime"
                        );

                        next FIELD;
                    }

                    $Self->Is(
                        $Ticket{$Field},
                        $Test->{UpdateResult}->{$Field},
                        "$Test->{Name} - Ticket field $Field"
                    );
                }
            }

            # Remove ticket appointment rule.
            $Selenium->find_element( '.RemoveButton', 'css' )->VerifiedClick();

            $Selenium->find_element( 'form#CalendarFrom button#SubmitAndContinue', 'css' )->VerifiedClick();
            $Self->True(
                1,
                "$Test->{Name} - Removed ticket appointment rule"
            );

            # Wait for daemon to do its magic.
            print "Waiting at most $SleepTime s until tasks are executed\n";
            ACTIVESLEEP:
            for my $Seconds ( 1 .. $SleepTime ) {
                my @List = $SchedulerDBObject->TaskList();
                last ACTIVESLEEP if !scalar @List;
                print "Sleeping for $Seconds seconds...\n";
                sleep 1;
            }

            # Make sure the cache is correct.
            $CacheObject->CleanUp(
                Type => "AppointmentList$Calendar{CalendarID}",
            );

            # Get fresh list of existing appointments in the calendar.
            @Appointments = $Kernel::OM->Get('Kernel::System::Calendar::Appointment')->AppointmentList(
                CalendarID => $Calendar{CalendarID},
            );
            $Self->False(
                scalar @Appointments,
                "$Test->{Name} - No appointments found in the calendar"
            );
        }

        # Stop daemon if it was started earlier in the test.
        if ( !$DaemonExitCode ) {
            `$^X $Daemon stop`;

            $Self->True(
                1,
                'Stopped daemon started earlier'
            );
        }

        #
        # Cleanup
        #

        my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

        # Delete test calendar.
        $Success = $DBObject->Do(
            SQL  => 'DELETE FROM calendar WHERE name = ?',
            Bind => [ \$CalendarName, ],
        );
        $Self->True(
            $Success,
            "Deleted test calendar - $CalendarName",
        );

        # Delete test ticket.
        $Success = $TicketObject->TicketDelete(
            TicketID => $TicketID,
            UserID   => 1,
        );
        $Self->True(
            $Success,
            "Deleted test ticket - $TicketID",
        );

        # Delete test queue.
        $Success = $DBObject->Do(
            SQL  => 'DELETE FROM queue WHERE id = ?',
            Bind => [ \$QueueID, ],
        );
        $Self->True(
            $Success,
            "Deleted test queue - $QueueID",
        );

        # Delete group-user relations.
        $Success = $DBObject->Do(
            SQL => "DELETE FROM group_user WHERE group_id = $GroupID",
        );
        $Self->True(
            $Success,
            "GroupUserDelete - $GroupName",
        );

        # Delete test group.
        $Success = $DBObject->Do(
            SQL  => "DELETE FROM groups WHERE name = ?",
            Bind => [ \$GroupName ],
        );
        $Self->True(
            $Success,
            "Deleted test group - $GroupID"
        );

        # Make sure cache is correct.
        for my $Cache (qw(Calendar Ticket Queue Group)) {
            $CacheObject->CleanUp( Type => $Cache );
        }
    },
);

1;
