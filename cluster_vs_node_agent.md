## Cluster Agent vs Node Agent

| Cecha | Cluster Agent | Node Agnet |
|---|---|---|
|Zakres działania| Cały k8s klaster| Pojedynczy węzeł |
|Typ połączenia| WebSocket to mgmt cluster (rancher)| WebSocket to mgmt cluster (rancher)|
| Dostęp do API servera (downstream K8s API)| Tak| Nie|
|Dostęp do hosta (downstream K8s node)|Nie|Tak|
|Zadania|Synchronizacja zasobów, odbieranie poleceń, komunikacja|Operacje na węźle, exec/logs, instalacja agentów|
