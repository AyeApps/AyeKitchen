import hashlib

import pytest
from httpx import AsyncClient


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


@pytest.mark.asyncio
async def test_reference_upload_and_download_roundtrip(client: AsyncClient, auth_headers):
    data = b"\xff\xd8\xff\xe0\x00\x10JFIFfakejpegbytes12345"
    sha = _sha256(data)
    ref_id = "ref-roundtrip-1"

    # Subir imagen
    put_resp = await client.put(
        f"/api/v1/backup/references/{ref_id}?sha256={sha}",
        headers={**auth_headers, "Content-Type": "image/jpeg"},
        content=data,
    )
    assert put_resp.status_code == 201
    info = put_resp.json()
    assert info["id"] == ref_id
    assert info["sha256"] == sha
    assert info["size_bytes"] == len(data)
    assert info["content_type"] == "image/jpeg"
    assert "updated_at" in info

    # Bajar imagen: mismos bytes y mismo tipo
    get_resp = await client.get(
        f"/api/v1/backup/references/{ref_id}",
        headers=auth_headers,
    )
    assert get_resp.status_code == 200
    assert get_resp.headers["content-type"].startswith("image/jpeg")
    assert get_resp.content == data


@pytest.mark.asyncio
async def test_reference_upload_and_download_heic(client: AsyncClient, auth_headers):
    data = b"fakeheicimagebytes\x00\x01\x02\x03"
    sha = _sha256(data)
    ref_id = "ref-heic-test"

    put_resp = await client.put(
        f"/api/v1/backup/references/{ref_id}?sha256={sha}",
        headers={**auth_headers, "Content-Type": "image/heic"},
        content=data,
    )
    assert put_resp.status_code == 201
    assert put_resp.json()["content_type"] == "image/heic"

    get_resp = await client.get(
        f"/api/v1/backup/references/{ref_id}",
        headers=auth_headers,
    )
    assert get_resp.status_code == 200
    assert get_resp.headers["content-type"].startswith("image/heic")
    assert get_resp.content == data


@pytest.mark.asyncio
async def test_reference_replace_changes_sha256(client: AsyncClient, auth_headers):
    ref_id = "ref-replace-test"
    data1 = b"original-reference-bytes-1"
    sha1 = _sha256(data1)

    # 1. Crear (201)
    put1 = await client.put(
        f"/api/v1/backup/references/{ref_id}?sha256={sha1}",
        headers={**auth_headers, "Content-Type": "image/jpeg"},
        content=data1,
    )
    assert put1.status_code == 201
    assert put1.json()["sha256"] == sha1

    # 2. Reemplazar (200)
    data2 = b"replaced-reference-bytes-2-different"
    sha2 = _sha256(data2)
    assert sha1 != sha2

    put2 = await client.put(
        f"/api/v1/backup/references/{ref_id}?sha256={sha2}",
        headers={**auth_headers, "Content-Type": "image/jpeg"},
        content=data2,
    )
    assert put2.status_code == 200
    info2 = put2.json()
    assert info2["id"] == ref_id
    assert info2["sha256"] == sha2
    assert info2["size_bytes"] == len(data2)

    # 3. GET devuelve los nuevos bytes
    get_resp = await client.get(
        f"/api/v1/backup/references/{ref_id}",
        headers=auth_headers,
    )
    assert get_resp.status_code == 200
    assert get_resp.content == data2


@pytest.mark.asyncio
async def test_reference_list_without_bytes(client: AsyncClient, auth_headers):
    # Lista vacía inicial
    list_init = await client.get("/api/v1/backup/references/", headers=auth_headers)
    assert list_init.status_code == 200
    assert list_init.json() == []

    # Subir dos referencias
    d1 = b"image-one"
    d2 = b"image-two"
    await client.put(
        f"/api/v1/backup/references/ref-1?sha256={_sha256(d1)}",
        headers={**auth_headers, "Content-Type": "image/jpeg"},
        content=d1,
    )
    await client.put(
        f"/api/v1/backup/references/ref-2?sha256={_sha256(d2)}",
        headers={**auth_headers, "Content-Type": "image/heic"},
        content=d2,
    )

    # Listar con / y sin /
    for path in ("/api/v1/backup/references/", "/api/v1/backup/references"):
        resp = await client.get(path, headers=auth_headers)
        assert resp.status_code == 200
        items = resp.json()
        assert len(items) == 2
        ids = {it["id"] for it in items}
        assert ids == {"ref-1", "ref-2"}
        for it in items:
            assert "data" not in it
            assert "size_bytes" in it
            assert "sha256" in it
            assert "content_type" in it
            assert "updated_at" in it


@pytest.mark.asyncio
async def test_reference_invalid_size(client: AsyncClient, auth_headers):
    max_size = 2 * 1024 * 1024
    too_large = b"x" * (max_size + 1)
    sha = _sha256(too_large)

    resp = await client.put(
        f"/api/v1/backup/references/ref-large?sha256={sha}",
        headers={**auth_headers, "Content-Type": "image/jpeg"},
        content=too_large,
    )
    assert resp.status_code == 413
    assert resp.json()["code"] == "BACKUP_TOO_LARGE"


@pytest.mark.asyncio
async def test_reference_invalid_content_type(client: AsyncClient, auth_headers):
    data = b"image-content"
    sha = _sha256(data)

    # Tipo no soportado
    resp = await client.put(
        f"/api/v1/backup/references/ref-png?sha256={sha}",
        headers={**auth_headers, "Content-Type": "image/png"},
        content=data,
    )
    assert resp.status_code == 422
    assert resp.json()["code"] == "INVALID_BACKUP"

    # Sin Content-Type
    resp_no_ct = await client.put(
        f"/api/v1/backup/references/ref-no-ct?sha256={sha}",
        headers=auth_headers,
        content=data,
    )
    assert resp_no_ct.status_code == 422
    assert resp_no_ct.json()["code"] == "INVALID_BACKUP"


@pytest.mark.asyncio
async def test_reference_invalid_id(client: AsyncClient, auth_headers):
    data = b"test-data"
    sha = _sha256(data)

    # Caracteres especiales inválidos
    invalid_ids = ["ref@invalid", "ref!image", "ref$val", "a" * 65]
    for bad_id in invalid_ids:
        resp = await client.put(
            f"/api/v1/backup/references/{bad_id}?sha256={sha}",
            headers={**auth_headers, "Content-Type": "image/jpeg"},
            content=data,
        )
        assert resp.status_code == 422
        assert resp.json()["code"] == "INVALID_BACKUP"


@pytest.mark.asyncio
async def test_reference_invalid_sha256(client: AsyncClient, auth_headers):
    data = b"test-content"
    wrong_sha = "0" * 64

    # Huella distinta
    resp = await client.put(
        f"/api/v1/backup/references/ref-bad-sha?sha256={wrong_sha}",
        headers={**auth_headers, "Content-Type": "image/jpeg"},
        content=data,
    )
    assert resp.status_code == 422
    assert resp.json()["code"] == "INVALID_BACKUP"

    # Sin huella o vacía
    resp_empty = await client.put(
        "/api/v1/backup/references/ref-empty-sha?sha256=",
        headers={**auth_headers, "Content-Type": "image/jpeg"},
        content=data,
    )
    assert resp_empty.status_code == 422
    assert resp_empty.json()["code"] == "INVALID_BACKUP"

    resp_missing = await client.put(
        "/api/v1/backup/references/ref-no-sha",
        headers={**auth_headers, "Content-Type": "image/jpeg"},
        content=data,
    )
    assert resp_missing.status_code == 422
    assert resp_missing.json()["code"] == "INVALID_BACKUP"


@pytest.mark.asyncio
async def test_reference_get_not_found(client: AsyncClient, auth_headers):
    resp = await client.get(
        "/api/v1/backup/references/does-not-exist",
        headers=auth_headers,
    )
    assert resp.status_code == 404
    assert resp.json()["code"] == "NOT_FOUND"


@pytest.mark.asyncio
async def test_reference_delete_is_idempotent(client: AsyncClient, auth_headers):
    data = b"delete-me"
    sha = _sha256(data)
    ref_id = "ref-del-1"

    # Subir imagen
    put_resp = await client.put(
        f"/api/v1/backup/references/{ref_id}?sha256={sha}",
        headers={**auth_headers, "Content-Type": "image/jpeg"},
        content=data,
    )
    assert put_resp.status_code == 201

    # Primer delete: 204
    del1 = await client.delete(
        f"/api/v1/backup/references/{ref_id}",
        headers=auth_headers,
    )
    assert del1.status_code == 204

    # Ya no existe
    get_resp = await client.get(
        f"/api/v1/backup/references/{ref_id}",
        headers=auth_headers,
    )
    assert get_resp.status_code == 404

    # Segundo delete: 204 aunque no exista
    del2 = await client.delete(
        f"/api/v1/backup/references/{ref_id}",
        headers=auth_headers,
    )
    assert del2.status_code == 204


@pytest.mark.asyncio
async def test_reference_workspace_isolation(
    client: AsyncClient,
    auth_headers,
    auth_headers_user_2,
):
    ref_id = "ref-shared-id"
    data1 = b"user1-secret-photo"
    sha1 = _sha256(data1)

    data2 = b"user2-completely-different-photo"
    sha2 = _sha256(data2)

    # 1. Usuario 1 sube ref-shared-id
    put1 = await client.put(
        f"/api/v1/backup/references/{ref_id}?sha256={sha1}",
        headers={**auth_headers, "Content-Type": "image/jpeg"},
        content=data1,
    )
    assert put1.status_code == 201

    # 2. Usuario 2 no ve la referencia en su lista
    list2 = await client.get("/api/v1/backup/references/", headers=auth_headers_user_2)
    assert list2.status_code == 200
    assert list2.json() == []

    # 3. Usuario 2 no puede descargarla
    get2 = await client.get(
        f"/api/v1/backup/references/{ref_id}",
        headers=auth_headers_user_2,
    )
    assert get2.status_code == 404
    assert get2.json()["code"] == "NOT_FOUND"

    # 4. Usuario 2 llama delete (204) pero no afecta al usuario 1
    del2 = await client.delete(
        f"/api/v1/backup/references/{ref_id}",
        headers=auth_headers_user_2,
    )
    assert del2.status_code == 204

    # Usuario 1 sigue teniendo su imagen intacta
    get1 = await client.get(
        f"/api/v1/backup/references/{ref_id}",
        headers=auth_headers,
    )
    assert get1.status_code == 200
    assert get1.content == data1

    # 5. Usuario 2 sube el MISMO id con sus propios bytes
    put2 = await client.put(
        f"/api/v1/backup/references/{ref_id}?sha256={sha2}",
        headers={**auth_headers_user_2, "Content-Type": "image/heic"},
        content=data2,
    )
    # Debe ser 201 para usuario 2 porque es nueva en su workspace
    assert put2.status_code == 201

    # 6. Cada usuario recibe su propia imagen con sus propios bytes y tipo
    resp_u1 = await client.get(
        f"/api/v1/backup/references/{ref_id}",
        headers=auth_headers,
    )
    assert resp_u1.status_code == 200
    assert resp_u1.headers["content-type"].startswith("image/jpeg")
    assert resp_u1.content == data1

    resp_u2 = await client.get(
        f"/api/v1/backup/references/{ref_id}",
        headers=auth_headers_user_2,
    )
    assert resp_u2.status_code == 200
    assert resp_u2.headers["content-type"].startswith("image/heic")
    assert resp_u2.content == data2
