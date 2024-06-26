import React from 'react';
import { List, ListItem, Text, TextContent } from '@patternfly/react-core';
import { ExternalLink } from '../../../../common/components/ui';
import { getOpenShiftNetworkingDocsLink } from '../../../../common/config/docs_links';

export interface UserManagedNetworkingTextContentProps {
  shouldDisplayLoadBalancersBullet?: boolean;
}

export const UserManagedNetworkingTextContent = ({
  shouldDisplayLoadBalancersBullet = false,
}: UserManagedNetworkingTextContentProps) => {
  return (
    <TextContent>
      <Text component={'p'}>
        Please refer to the{' '}
        <ExternalLink href={getOpenShiftNetworkingDocsLink()}>
          OpenShift networking documentation
        </ExternalLink>{' '}
        to configure your cluster's networking, including:{' '}
      </Text>
      <List>
        <ListItem>DHCP or static IP Addresses</ListItem>
        {shouldDisplayLoadBalancersBullet && <ListItem>Load balancers</ListItem>}
        <ListItem>Network ports</ListItem>
        <ListItem>DNS</ListItem>
      </List>
    </TextContent>
  );
};
