# --
# Copyright (C) 2001-2018 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::Notification::AgentCloudServicesDisabled;

use parent 'Kernel::Output::HTML::Base';

use strict;
use warnings;
use utf8;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::Output::HTML::Layout',
    'Kernel::System::Group',
);

sub Run {
    my ( $Self, %Param ) = @_;

    my $Output = '';

    # check if cloud services are disabled
    my $CloudServicesDisabled = $Kernel::OM->Get('Kernel::Config')->Get('CloudServices::Disabled') || 0;

    return '' if !$CloudServicesDisabled;
    return '' if $Param{Type} ne 'Admin';

    my $Group = $Param{Config}->{Group} || 'admin';

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    my $HasPermission = $Kernel::OM->Get('Kernel::System::Group')->PermissionCheck(
        UserID    => $Self->{UserID},
        GroupName => $Group,
        Type      => 'rw',
    );

    # notification should only be visible for administrators
    if ( !$HasPermission ) {
        return '';
    }

    my $Text = '<a href="'
        . $LayoutObject->{Baselink}
        . 'Action=AdminSystemConfiguration;Subaction=Edit;SysConfigSubGroup=Core;SysConfigGroup=CloudService'
        . '">';
    $Text .= $LayoutObject->{LanguageObject}->Translate('Enable cloud services to unleash all OTRS features!');
    $Text .= '</a>';

    return $LayoutObject->Notify(
        Data     => $Text,
        Priority => 'Info',
    );
}
1;
