---
title: AddressService
aliases:
  - AddressService (vpc)
proto_file: kacho/cloud/vpc/v1/address_service.proto
category: rpc
backend: kacho-vpc
backend_port: 9090
visibility: public
domain: vpc
related_resource: "[[resources/vpc-address]]"
methods_count: 9
async_methods: 4
tags:
  - rpc
  - kacho-vpc
  - address
  - ipam
---

# AddressService (vpc)

**Proto**: `kacho-proto/proto/kacho/cloud/vpc/v1/address_service.proto`
**Backend**: `kacho-vpc:9090`
**Public/Internal**: public

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetAddressRequest | Address | sync | |
| GetByValue | GetAddressByValueRequest | Address | sync | lookup по `?address=1.2.3.4` |
| List | ListAddressesRequest | ListAddressesResponse | sync | |
| ListBySubnet | ListAddressesBySubnetRequest | ListAddressesBySubnetResponse | sync | |
| Create | CreateAddressRequest | operation.Operation | **async** | external/internal v4/v6 |
| Update | UpdateAddressRequest | operation.Operation | **async** | name/labels/desc/reserved-flag |
| Delete | DeleteAddressRequest | operation.Operation | **async** | FailedPrecondition если `used_by` |
| Move | MoveAddressRequest | operation.Operation | **async** | cross-folder |
| ListOperations | ListAddressOperationsRequest | ListAddressOperationsResponse | sync | |

## REST mapping

| HTTP                                            | Method         |
| ----------------------------------------------- | -------------- |
| `GET /vpc/v1/addresses/{address_id}`            | Get            |
| `GET /vpc/v1/addresses:byValue`                 | GetByValue     |
| `GET /vpc/v1/addresses`                         | List           |
| `GET /vpc/v1/addresses:bySubnet`                | ListBySubnet   |
| `POST /vpc/v1/addresses`                        | Create         |
| `PATCH /vpc/v1/addresses/{address_id}`          | Update         |
| `DELETE /vpc/v1/addresses/{address_id}`         | Delete         |
| `POST /vpc/v1/addresses/{address_id}:move`      | Move           |
| `GET /vpc/v1/addresses/{address_id}/operations` | ListOperations |

## Related (internal)

- [[vpc-internal-address-service]] — IPAM-allocate (ephemeral), SetAddressReference (used_by).
- [[vpc-internal-address-pool-service]] — pool binding (override per-Address).

## See also

[[../packages/vpc-apps-kacho-api-address]] [[../resources/vpc-address]]

#rpc #kacho-vpc #address #ipam
