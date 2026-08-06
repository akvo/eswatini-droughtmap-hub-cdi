import pytest
from unittest import mock

from .. import sync_geonode_publications_job as job


@pytest.fixture(autouse=True)
def mock_env(monkeypatch):
    monkeypatch.setattr(job, "geonode_url", "http://test.geonode.com")
    monkeypatch.setattr(job, "username", "testuser")
    monkeypatch.setattr(job, "password", "secret")
    monkeypatch.setattr(job, "hub_url", "http://test.hub.com")
    monkeypatch.setattr(job, "hub_api_key", "test-key")


def resource(**overrides):
    base = {
        "pk": 42,
        "title": "CDI_202401",
        "date": "2024-01-01T00:00:00Z",
        "detail_url": "http://test.geonode.com/datasets/42",
        "embed_url": "",
        "thumbnail_url": None,
        "download_url": "http://test.geonode.com/download/42",
        "filesize": 1234,
    }
    base.update(overrides)
    return base


def test_build_payload_maps_fields_and_drops_blanks():
    payload = job.build_payload(resource(), "cdi-raster-map")
    assert payload == {
        "geonode_id": 42,
        "category": "cdi-raster-map",
        "title": "CDI_202401",
        "year_month": "2024-01-01",
        "detail_url": "http://test.geonode.com/datasets/42",
        "download_url": "http://test.geonode.com/download/42",
        "file_size": 1234,
    }


def test_build_payload_normalises_day_and_rejects_bad_input():
    assert job.build_payload(
        resource(date="2024-03-17"), "spi-raster-map"
    )["year_month"] == "2024-03-01"
    assert job.build_payload(resource(date=""), "spi-raster-map") is None
    assert job.build_payload(resource(title=None), "spi-raster-map") is None


def test_push_publication_sends_api_key():
    with mock.patch("requests.post") as post:
        post.return_value = mock.Mock(status_code=201)
        assert job.push_publication({"geonode_id": 42}) is True
    args, kwargs = post.call_args
    assert args[0] == "http://test.hub.com/api/v1/geonode/publications"
    assert kwargs["headers"] == {"X-API-Key": "test-key"}
    assert kwargs["verify"] is True


def test_push_publication_reports_failure():
    with mock.patch("requests.post") as post:
        post.return_value = mock.Mock(status_code=403, text="Forbidden")
        assert job.push_publication({"geonode_id": 42}) is False


def test_sync_category_pages_until_total_reached():
    pages = [
        {"resources": [resource(pk=i + 1) for i in range(job.PAGE_SIZE)],
         "total": job.PAGE_SIZE + 1},
        {"resources": [resource(pk=99)], "total": job.PAGE_SIZE + 1},
    ]
    with mock.patch.object(job, "fetch_resources", side_effect=pages) as fetch:
        with mock.patch.object(job, "push_publication", return_value=True):
            synced, failed = job.sync_category("cdi-raster-map")
    assert (synced, failed) == (job.PAGE_SIZE + 1, 0)
    assert fetch.call_count == 2


def test_main_skips_when_hub_not_configured(monkeypatch, capfd):
    monkeypatch.setattr(job, "hub_url", None)
    with mock.patch.object(job, "sync_category") as sync:
        job.main()
    sync.assert_not_called()
    assert "skipping portal sync" in capfd.readouterr().out
