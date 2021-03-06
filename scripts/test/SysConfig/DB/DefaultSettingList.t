# --
# Copyright (C) 2001-2018 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

## no critic (Modules::RequireExplicitPackage)
use strict;
use warnings;
use utf8;

use Kernel::System::VariableCheck qw( IsArrayRefWithData IsHashRefWithData );

use vars (qw($Self));

$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $HelperObject      = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');
my $SysConfigObject   = $Kernel::OM->Get('Kernel::System::SysConfig');
my $SysConfigDBObject = $Kernel::OM->Get('Kernel::System::SysConfig::DB');

my %Setting1 = $SysConfigObject->SettingGet(
    Name => 'Frontend::DebugMode',
);

my %Setting2 = $SysConfigObject->SettingGet(
    Name => 'SystemID',
);

# Lock 2 settings
my $GUID1 = $SysConfigObject->SettingLock(
    Name   => 'Frontend::DebugMode',
    UserID => 1,
);

$Self->True(
    $GUID1,
    'Frontend::DebugMode locked successfully.'
);

my $GUID2 = $SysConfigObject->SettingLock(
    Name   => 'SystemID',
    UserID => 1,
);

$Self->True(
    $GUID2,
    'SystemID locked successfully.'
);

my $UpdateSuccess = $SysConfigDBObject->DefaultSettingUpdate(
    %Setting1,
    ExclusiveLockGUID => $GUID1,
    EffectiveValue    => 'Updated setting',
    UserID            => 1,
);

$Self->True(
    $UpdateSuccess,
    'Setting Frontend::DebugMode updated successfully.',
);

# Since we updated 1 setting, we have 1 locked setting and 1 dirty setting.
my @LockedSettings = $SysConfigDBObject->DefaultSettingList(
    Locked => 1,
);

$Self->IsDeeply(
    \@LockedSettings,
    [
        {
            'DefaultID'         => $Setting2{DefaultID},
            'ExclusiveLockGUID' => $GUID2,
            'IsDirty'           => '0',
            'Name'              => 'SystemID',
            'XMLContentRaw'     => '<Setting Name="SystemID" Required="1" Valid="1" ConfigLevel="200">
        <Description Translatable="1">Defines the system identifier. Every ticket number and http session string contains this ID. This ensures that only tickets which belong to your system will be processed as follow-ups (useful when communicating between two instances of OTRS).</Description>
        <Navigation>Core</Navigation>
        <Value>
            <Item ValueType="String" ValueRegex="^\\d+$">10</Item>
        </Value>
    </Setting>',
            'XMLFilename' => 'Framework.xml',
        },
    ],
    'Check locked settings',
);

my @DirtySettings = $SysConfigDBObject->DefaultSettingList(
    IsDirty => 1,
);
$Self->IsDeeply(
    \@DirtySettings,
    [
        {
            'DefaultID'         => $Setting1{DefaultID},
            'ExclusiveLockGUID' => '0',
            'IsDirty'           => '1',
            'Name'              => 'Frontend::DebugMode',
            'XMLContentRaw'     => '<Setting Name="Frontend::DebugMode" Required="0" Valid="1" ConfigLevel="100">
        <Description Translatable="1">Enables or disables the debug mode over frontend interface.</Description>
        <Navigation>Frontend::Base</Navigation>
        <Value>
            <Item ValueType="Checkbox">0</Item>
        </Value>
    </Setting>',
            'XMLFilename' => 'Framework.xml'
        },
    ],
    'Check dirty settings',
);

# We can't compare all settings, it depends on installed packages, but we know there are at least 1700 settings.
my @SettingList = $SysConfigDBObject->DefaultSettingList();

$Self->True(
    scalar @SettingList > 1700,
    'Make sure there are at least 1700 settings.',
);

1;
