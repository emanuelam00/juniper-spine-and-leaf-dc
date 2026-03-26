# Juniper Spine-Leaf Fabric Monitoring Stack

Production-ready comprehensive monitoring and observability solution for a Juniper datacenter fabric with 4 spine switches (QFX5220-32CD) and 60 leaf switches (QFX5120-48Y).

## Quick Start

### Prerequisites
- Docker Engine 20.10+
- Docker Compose 2.0+
- 8GB RAM minimum (16GB recommended)
- 50GB disk space for time-series metrics (30-day retention)

### Deploy the Stack

```bash
# Create environment file
cat > .env << EOF
GF_PASSWORD=your-secure-grafana-password
SNMP_PASSWORD=ChangeMe123!
GNMI_PASSWORD=ChangeMe123!
POSTGRES_USER=admin
POSTGRES_PASSWORD=your-postgres-password
INFLUX_USER=admin
INFLUX_PASSWORD=your-influx-password
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
PAGERDUTY_SERVICE_KEY=your-pagerduty-key
SMTP_PASSWORD=your-smtp-password
EOF

# Start the monitoring stack
docker-compose up -d

# Verify all services are running
docker-compose ps
```

### Access Services

| Service | URL | Default Credentials |
|---------|-----|-------------------|
| Grafana | http://localhost:3000 | admin / (from .env) |
| Prometheus | http://localhost:9090 | N/A |
| Alertmanager | http://localhost:9093 | N/A |
| Loki | http://localhost:3100 | N/A |
| InfluxDB | http://localhost:8086 | admin / (from .env) |

## File Structure

```
monitoring/
├── docker-compose.yml                 # Main Docker Compose configuration
├── README.md                          # This file
│
├── docs/
│   └── MONITORING.md                 # Comprehensive monitoring guide
│
├── prometheus/
│   ├── prometheus.yml                # SNMP & gNMI scrape configs
│   └── alert_rules.yml               # Prometheus alerting rules
│
├── telegraf/
│   └── telegraf.conf                 # SNMP, gNMI, syslog collectors
│
├── grafana/
│   ├── fabric-overview.json          # Main fabric overview dashboard
│   └── provisioning/
│       └── datasources/
│           └── prometheus.yml        # Grafana datasource config
│
├── alertmanager/
│   └── alertmanager.yml              # Alert routing & notifications
│
├── loki/
│   └── loki-config.yml               # Log storage configuration
│
├── promtail/
│   └── promtail-config.yml           # Syslog to Loki pipeline
│
└── snmp-exporter/
    └── snmp.yml                      # SNMP module definitions
```

## Architecture

### Data Flow

```
Network Devices (Spines/Leaves/Firewalls)
        ↓
    ↙   ↓   ↘
  SNMP gNMI Syslog
   ↓    ↓     ↓
   ├─→ SNMP  ├─→ gNMI  ├─→ Promtail
   │  Exporter │ Collector │   ↓
   │    ↓     │    ↓      │  Loki
   └────┬─────┴────┬──────┘   ↓
        ↓          ↓       Grafana
     Telegraf      │
        ↓          ↓
    Prometheus ←───┘
        ↓
    ├─→ Alertmanager → Slack/PagerDuty/Email
    ├─→ Grafana (Visualization)
    └─→ InfluxDB (Long-term storage)
```

### Components

| Component | Role | Port |
|-----------|------|------|
| Prometheus | Time-series database & alerting | 9090 |
| Telegraf | Multi-source metrics collector | 9273 |
| SNMP Exporter | SNMP to Prometheus bridge | 9116 |
| Grafana | Visualization & dashboarding | 3000 |
| Alertmanager | Alert routing & notification | 9093 |
| Loki | Log aggregation | 3100 |
| Promtail | Syslog to Loki shipper | 1514, 3101 |
| InfluxDB | Long-term metrics storage | 8086 |
| PostgreSQL | Optional backend database | 5432 |
| Node Exporter | Host metrics | 9100 |
| cAdvisor | Container metrics | 8080 |

## Configuration Guide

### 1. Configure SNMP v3 on Juniper Devices

SSH to each spine and leaf and apply:

```junos
# Set SNMP v3 credentials
set snmp v3 usm local-engine user monitoring authentication-protocol md5 authentication-password "ChangeMe123!"
set snmp v3 usm local-engine user monitoring privacy-protocol aes privacy-password "ChangeMe456!"
set snmp v3 vacm security-to-group security-model usm security-name monitoring group monitoring
set snmp v3 vacm access group monitoring context default read-view all-mib
set snmp v3 access group monitoring context default security-model usm security-level auth-privacy

# Enable SNMP
set snmp trap version v3

# Configure syslog forwarding
set system syslog host 10.254.10.10 any notice
set system syslog host 10.254.10.10 bgp notice
set system syslog host 10.254.10.10 routing-daemon notice

commit
```

### 2. Update Prometheus Configuration

Edit `prometheus/prometheus.yml`:

- Replace `10.255.0.1-4` with actual spine management IPs
- Replace `10.255.1.1-60` with actual leaf management IPs
- Verify SNMP credentials match device configuration
- Update `alertmanager` address if running on different host

### 3. Configure Alertmanager Notifications

Edit `alertmanager/alertmanager.yml`:

- Add Slack webhook URL to environment
- Configure PagerDuty service key
- Set email address and SMTP server
- Customize alert routing rules by severity

### 4. Enable Streaming Telemetry (Optional)

For real-time data instead of 5-minute polling:

```junos
# Configure JTI on spines
set services jti request interface-statistics
set services jti request bgp-rib
set services jti request system
set services jti stream interface-stats frequency 1000
set services jti streaming-server subscriber-server port 50000
set services jti streaming-server subscriber-server transport grpc

commit
```

Update `telegraf/telegraf.conf` with device hostnames.

## Key Metrics Monitored

### Interface Metrics
- Operational status (up/down)
- Inbound/outbound octets, packets, errors, discards
- Optical power levels (RX/TX)
- CRC errors
- Link speed

### BGP/EVPN Metrics
- Peer state (established/down)
- Route count (received/sent)
- Update message rate
- EVPN MAC count
- Type-5 route availability

### System Metrics
- CPU utilization
- Memory utilization
- Temperature (intake/exhaust)
- Power supply status
- Fan status

### Fabric Metrics
- ECMP load balance distribution
- Spine reachability
- Leaf isolation detection
- Convergence time (on failures)

## Alert Rules

80+ production-ready alert rules covering:

- **Critical**: Device down, interface down, spine failure, high optical errors
- **Warning**: High utilization, BGP instability, temperature warnings
- **Info**: Route count changes, MAC movements, configuration updates

See `prometheus/alert_rules.yml` for complete list with thresholds.

## Dashboards

### Fabric Overview
- Spine/leaf health grid
- BGP session status
- Top utilized interfaces
- System health heatmap
- Error rate trending

### Per-Device Dashboard (Templates Available)
- Interface detail view
- BGP neighbor status
- System resource trends
- Syslog stream

### BGP/EVPN Dashboard
- Session matrix
- Route count trends
- Flapping detection
- Convergence timing

### Capacity Planning Dashboard
- Growth trends (30/60/90 days)
- Upgrade recommendations
- Resource projections

## Troubleshooting

### Services Not Starting

```bash
# Check service logs
docker-compose logs prometheus
docker-compose logs telegraf
docker-compose logs grafana

# Verify network connectivity
docker network inspect monitoring

# Check resource usage
docker stats
```

### Missing SNMP Data

```bash
# Test SNMP connectivity from collector
docker-compose exec telegraf bash
snmpwalk -v3 -u monitoring -l authPriv -a MD5 -A ChangeMe123! -x AES -X ChangeMe456! 10.255.0.1 1.3.6.1.2.1.1.1.0

# Check Prometheus scrape status
curl http://localhost:9090/api/v1/targets
```

### High Memory Usage

```bash
# Check Prometheus retention
curl http://localhost:9090/api/v1/admin/stats/db

# Reduce retention in prometheus.yml if needed
--storage.tsdb.retention.time=7d  # was 30d
```

### Network Device Not Appearing

1. Verify management IP is reachable
2. Confirm SNMP v3 credentials are correct
3. Check firewall allows UDP 161 (SNMP)
4. Test with snmpwalk from a host with network access

## Backup & Restore

### Backup Prometheus Data

```bash
docker-compose exec prometheus tar czf - /prometheus | gzip > prometheus-backup.tar.gz
```

### Backup Grafana Dashboards

```bash
curl -H "Authorization: Bearer eyJrIjoixxxxx" http://localhost:3000/api/dashboards/db/fabric-overview > dashboard-backup.json
```

### Backup All Volumes

```bash
docker-compose exec prometheus tar czf /tmp/prometheus.tar.gz /prometheus
docker-compose exec grafana tar czf /tmp/grafana.tar.gz /var/lib/grafana
docker cp prometheus:/tmp/prometheus.tar.gz ./backups/
docker cp grafana:/tmp/grafana.tar.gz ./backups/
```

## Performance Tuning

### For Large Fabric (100+ devices)

```yaml
# prometheus.yml
global:
  scrape_interval: 30s  # Increase from 15s
  evaluation_interval: 30s

# alert_rules.yml
interval: 60s  # Increase from 30s

# telegraf.conf
[agent]
  interval = "30s"  # Increase from 10s
  metric_batch_size = 2000  # Increase from 1000
```

### Storage Optimization

```bash
# Reduce retention
docker-compose.yml - prometheus command:
--storage.tsdb.retention.time=14d  # from 30d

# Enable compression
--storage.tsdb.max-block-duration=8h
--storage.tsdb.min-block-duration=2h
```

## Scaling Considerations

### Multi-Region Deployment

```yaml
# Use remote_write in prometheus.yml
remote_write:
  - url: "http://central-prometheus:9090/api/v1/write"
    queue_config:
      max_shards: 10
```

### High Availability

Run multiple Prometheus instances with Thanos for:
- Query federation
- Long-term storage (S3/GCS)
- Deduplication across regions

## Security Hardening

### Network Isolation

```bash
# Restrict to management network only
docker-compose.yml:
ports:
  - "10.254.10.100:9090:9090"  # Bind to specific management IP
```

### Authentication

```yaml
# Enable Grafana LDAP/OIDC
grafana:
  environment:
    GF_AUTH_LDAP_ENABLED: 'true'
    GF_AUTH_LDAP_CONFIG_PATH: '/etc/grafana/ldap.toml'
```

### TLS for Metrics

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'snmp'
    scheme: https
    tls_config:
      ca_file: /etc/prometheus/ca.crt
```

## Maintenance

### Weekly Tasks
- Review alerting patterns
- Check disk usage trends
- Verify backup integrity

### Monthly Tasks
- Review retention policies
- Analyze capacity growth
- Test disaster recovery procedures

### Quarterly Tasks
- Upgrade base images
- Update alert thresholds based on growth
- Audit alerting rules for optimization

## Support & Documentation

- Comprehensive monitoring guide: `../docs/MONITORING.md`
- Prometheus docs: https://prometheus.io/docs
- Grafana docs: https://grafana.com/docs/grafana/
- Loki docs: https://grafana.com/docs/loki/
- Juniper monitoring: https://www.juniper.net/documentation

## Version Information

- Prometheus: 2.45+
- Grafana: 10.0+
- Telegraf: 1.28+
- Loki: 2.9+
- InfluxDB: 2.7+

## License

This monitoring stack configuration is provided as-is for use with Juniper datacenter fabrics. Refer to individual component licenses for usage terms.

## Last Updated

2026-03-25
