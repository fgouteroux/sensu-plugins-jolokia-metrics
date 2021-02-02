[![Sensu Bonsai Asset](https://img.shields.io/badge/Bonsai-Download%20Me-brightgreen.svg?colorB=89C967&logo=sensu)](https://bonsai.sensu.io/assets/sensu-plugins/sensu-plugins-jolokia-metrics)
[![Build Status](https://travis-ci.org/fgouteroux/sensu-plugins-jolokia-metrics.svg?branch=master)](https://travis-ci.org/fgouteroux/sensu-plugins-jolokia-metrics)

## Sensu Jolokia Metrics Plugin

- [Overview](#overview)
- [Usage examples](#usage-examples)
- [Configuration](#configuration)
  - [Sensu Go](#sensu-go)
    - [Asset definition](#asset-definition)
    - [Check definition](#check-definition)
  - [Sensu Core](#sensu-core)
    - [Check definition](#check-definition)
- [Functionality](#functionality)
- [Installation](#installation)

### Overview 

This plugin provides native HTTP instrumentation for jolokia metrics collection.

The Sensu assets packaged from this repository are built against the Sensu ruby runtime environment. When using these assets as part of a Sensu Go resource (check, mutator or handler), make sure you include the corresponding Sensu ruby runtime asset in the list of assets needed by the resource.  The current ruby-runtime assets can be found [here](https://bonsai.sensu.io/assets/sensu/sensu-ruby-runtime) in the [Bonsai Asset Index](bonsai.sensu.io)

#### Files
 * bin/jolokia-metrics.rb

## Usage examples

**jolokia-metrics.rb**
```
Usage: jolokia-metrics.rb (options)
    -u, --url URL          Full URL to the jolokia endpoint
    -f, --file FILE        File path with metrics name to retrieve
    -s, --scheme SCHEME    Metric naming scheme, text to prepend to metric
    -d, --debug            Include debug output, should not use in production.
    -k, --insecure         Disable SSL verification
```

### Configuration
#### Sensu Go
##### Asset registration

Assets are the best way to make use of this plugin. If you're not using an asset, please consider doing so! If you're using sensuctl 5.13 or later, you can use the following command to add the asset: 

`sensuctl asset add fgouteroux/sensu-plugins-jolokia-metrics`

If you're using an earlier version of sensuctl, you can download the asset definition from [this project's Bonsai Asset Index page](https://bonsai.sensu.io/assets/fgouteroux/sensu-plugins-jolokia-metrics).

##### Asset definition

```yaml
---
type: Asset
api_version: core/v2
metadata:
  name: sensu-plugins-jolokia-metrics
spec:
  url: https://assets.bonsai.sensu.io/30d8361243af8c7806e2d6db4a6dc576dab02966/sensu-plugins-jolokia-metrics_0.0.2_centos_linux_amd64.tar.gz
  sha512: eb39c9c92984975c9339dcaddefba9fa6d1bc52b6ae73693ca4d4e6068a0b320e3d6eeb69afdd8c1210222953effd520ffc24687eba7d433c92c44f797c99c5c
```

##### Check definition

```yaml
---
type: CheckConfig
spec:
  command: "jolokia-metrics.rb --url http://localhost:8778/jolokia/read --file /tmp/metrics.beans.yaml"
  handlers: []
  high_flap_threshold: 0
  interval: 10
  low_flap_threshold: 0
  publish: true
  runtime_assets:
  - sensu-plugins-jolokia-metrics
  - sensu-ruby-runtime
  subscriptions:
  - linux
  output_metric_format: graphite_plaintext
  output_metric_handlers:
  - graphite
```
#### Sensu Core
##### Check definition
```json
{
  "checks": {
    "check-jolokia-metrics": {
    "command": "jolokia-metrics.rb --url http://localhost:8778/jolokia/read --file /tmp/metrics.beans.yaml",
    "subscribers": [
      "servers"
    ],
    "interval": 60
    }
  }
}
```

### Functionality

**jolokia-metrics.rb**

Collect jolokia metrics defined in an yaml file with one single post request.

each json should follow jolokia's api POST read request <https://jolokia.org/reference/html/protocol.html>:

```json
{
   "type":"read",
   "mbean":"java.lang:type=Threading",
   "attribute":"ThreadCount",
}
```

**/tmp/metrics.beans.yaml**
```yaml
data:
  - {"type": "read",  "mbean": "java.lang:type=Memory"}
  - {"type": "read",  "mbean": "java.lang:type=Threading"}
  - {"type": "read",  "mbean": "java.lang:type=GarbageCollector,name=*"}
  - {"type": "read",  "mbean": "kafka.server:type=BrokerTopicMetrics,name=MessagesInPerSec"}
  - {"type": "read",  "mbean": "kafka.server:type=BrokerTopicMetrics,name=BytesInPerSec"}
  - {"type": "read",  "mbean": "kafka.server:type=BrokerTopicMetrics,name=BytesOutPerSec"}
  - {"type": "read", "mbean": "Catalina:name=*,type=ThreadPool", "attribute": "acceptorThreadCount,currentThreadsBusy"}
```

It's possible to define custom patterns to escape metric characters.
Is some case java mbean can be named like this: 'java.lang:type=Memory'


To escape, add the key 'patterns' in config file:

```yaml
patterns:
  - ['*', '_']    # default value
  - ['.', '_']    # default value
  - [',', '.']    # default value
  - [' ', '_']    # default value
  - ['(', '']     # default value
  - [')', '']     # default value
  - [':', '.']    # default value
  - ['name=', '']
  - ['type=', '']
  - ['request=', '']
```

If this key 'patterns' is not defined default value are applied.

It's possible to map result value to fit graphite pattern.
Is some case the result value can be boolean: DOWN/UP => 0/1

To map this kind of result, add the key 'result_mapper' in config file:

```yaml
result_mapper:
  - ['UP', '1']    # default value
  - ['DOWN', '0']    # default value
```

If this key 'result_mapper' is not defined default value are applied.

## Installation

### Sensu Go

See the instructions above for [asset registration](#asset-registration)

### Sensu Core
Install and setup plugins on [Sensu Core](https://docs.sensu.io/sensu-core/latest/installation/installing-plugins/)
