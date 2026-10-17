import json
import os
import re
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request

UUID = re.compile(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
SPLITTERS = re.compile(r'[\s;&|<>$`\'"\\()#*?\[\]!~{}]+')
CLI_REPO = 'sirinsidiator/ESOAddOnUploaderCLI'
CLI_ASSET = 'ESOAddOnUploaderCli-linux.tar.gz'
NOTES_LIMIT = 10000


def command_data(value):
    return value.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')


def mask(value):
    if not value:
        return
    print('::add-mask::' + command_data(value))
    for piece in SPLITTERS.split(value):
        if len(piece) >= 4 and piece != value:
            print('::add-mask::' + command_data(piece))
    sys.stdout.flush()


def fail(title, text):
    print('::error title=%s::%s' % (title, text))
    sys.exit(1)


def credential(name):
    raw = os.environ.get('UPLOAD_' + name, '')
    value = raw.rstrip('\r\n')
    mask(raw)
    mask(value)
    if value != raw:
        print('::notice title=%s cleaned::A line break at the end of %s was dropped; it is never part of a password typed into a form.' % (name, name))
    if not value:
        fail('%s is empty' % name, 'The %s secret is empty or missing in this repository.' % name)
    if value != value.strip():
        print('::notice title=%s has edge spaces::%s starts or ends with a space; it is sent exactly as stored.' % (name, name))
    return value


def download(url, path):
    last = None
    for attempt in range(4):
        try:
            request = urllib.request.Request(url, headers={'User-Agent': 'eso-bethesda-upload'})
            with urllib.request.urlopen(request, timeout=120) as response, open(path, 'wb') as out:
                out.write(response.read())
            return
        except Exception as err:
            last = err
            time.sleep(10 * (attempt + 1))
    fail('ESOAddOnUploaderCli download failed', '%s (%s)' % (url, last))


def cli_url(version):
    if version != 'latest':
        return 'https://github.com/%s/releases/download/%s/%s' % (CLI_REPO, version, CLI_ASSET)
    request = urllib.request.Request('https://api.github.com/repos/%s/releases/latest' % CLI_REPO,
                                     headers={'User-Agent': 'eso-bethesda-upload', 'Accept': 'application/vnd.github+json'})
    with urllib.request.urlopen(request, timeout=60) as response:
        release = json.load(response)
    for asset in release.get('assets', []):
        if asset.get('name') == CLI_ASSET:
            return asset['browser_download_url']
    fail('ESOAddOnUploaderCli not found', 'The latest %s release has no %s.' % (CLI_REPO, CLI_ASSET))


def main():
    username = credential('BNET_USERNAME')
    password = credential('BNET_PASSWORD')
    addon_id = os.environ.get('UPLOAD_ADDON_ID', '').strip()
    version = os.environ.get('UPLOAD_VERSION', '').strip()
    zip_file = os.environ.get('UPLOAD_ZIP_FILE', '').strip()
    notes_file = os.environ.get('UPLOAD_NOTES_FILE', '').strip()
    concurrency = os.environ.get('UPLOAD_CONCURRENCY', '1').strip() or '1'
    publish = os.environ.get('UPLOAD_PUBLISH', 'true').strip().lower() != 'false'
    cli_version = os.environ.get('UPLOAD_CLI_VERSION', '').strip() or 'latest'

    if not addon_id:
        fail('No Bethesda.net add-on ID', "addon_id is empty: this add-on has no Bethesda.net page yet, or the workflow's addon_id was never filled in.")
    if not UUID.match(addon_id):
        fail('Bad add-on ID', "addon_id '%s' is not an ID like dac0d37e-2d2f-4813-a148-6198c2d54687 (the part of the mods.bethesda.net address after /details/)." % addon_id)
    if not version:
        fail('No version', 'version is empty.')
    if len(version) > 255:
        fail('Version too long', 'Bethesda.net takes a version label of at most 255 characters.')
    if not os.path.isfile(zip_file):
        fail('Zip not found', 'zip_file not found: %s' % zip_file)
    if not os.path.isfile(notes_file):
        fail('Release notes not found', 'release_notes_file not found: %s' % notes_file)
    if not concurrency.isdigit() or int(concurrency) < 1:
        fail('Bad concurrency', 'concurrency must be a whole number of 1 or more, not %s' % concurrency)
    notes = open(notes_file, encoding='utf-8', errors='replace').read()
    if len(notes.encode('utf-8')) > NOTES_LIMIT:
        fail('Release notes too long', '%s is %d bytes; Bethesda.net takes at most %d.' % (notes_file, len(notes.encode('utf-8')), NOTES_LIMIT))

    work = tempfile.mkdtemp(prefix='eso-bethesda-upload-')
    archive = os.path.join(work, CLI_ASSET)
    url = cli_url(cli_version)
    print('Downloading ESOAddOnUploaderCli (%s)' % cli_version)
    download(url, archive)
    with tarfile.open(archive) as tar:
        try:
            tar.extractall(work, filter='data')
        except TypeError:
            tar.extractall(work)
    cli = os.path.join(work, 'ESOAddOnUploaderCli')
    os.chmod(cli, 0o755)
    if subprocess.run([cli, '--help'], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
        fail('ESOAddOnUploaderCli does not start', 'The downloaded uploader exited with an error on --help.')

    config = os.path.join(work, 'upload-config.json')
    with open(config, 'w', encoding='utf-8') as out:
        json.dump({'addonId': addon_id, 'version': version, 'note': notes}, out)

    command = [cli, 'upload', os.path.abspath(zip_file), '--config', config, '--concurrency', concurrency]
    if not publish:
        command.append('--no-publish')
        print('::notice title=Test upload::publish is false, so the upload is not published.')
    env = dict(os.environ, BNET_USERNAME=username, BNET_PASSWORD=password)
    for key in [k for k in env if k.startswith('UPLOAD_BNET_')]:
        del env[key]
    print('Uploading %s %s to Bethesda.net add-on %s' % (os.path.basename(zip_file), version, addon_id))
    sys.stdout.flush()
    code = subprocess.run(command, env=env, stdin=subprocess.DEVNULL, cwd=work).returncode
    if code != 0:
        fail('Bethesda.net upload failed', 'ESOAddOnUploaderCli exited with %d. The username and password reached it whole, whatever characters they contain; check that they are current and that MFA is off.' % code)
    print('::notice title=Upload done::%s %s uploaded to Bethesda.net%s.' % (os.path.basename(zip_file), version, '' if publish else ' (not published)'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
