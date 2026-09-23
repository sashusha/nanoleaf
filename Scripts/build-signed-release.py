#!/usr/bin/env python3
"""Build an intact signed app; never store signing secrets in the repository."""
import argparse
import hashlib
import pathlib
import plistlib
import shutil
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
def run(*args):
    subprocess.run(args, cwd=ROOT, check=True)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--identity', required=True, help='Code-signing identity name or SHA-1; - for ad-hoc testing only')
    parser.add_argument('--version', required=True)
    parser.add_argument('--self-signed', action='store_true', help='Use a persistent local certificate; not eligible for notarization')
    parser.add_argument('--notary-profile', help='Existing notarytool Keychain profile; no credentials on the command line')
    parser.add_argument('--output', required=True, type=pathlib.Path)
    args = parser.parse_args()
    if args.self_signed and (args.identity == '-' or args.notary_profile):
        parser.error('Self-signed mode requires a certificate and cannot use notarization.')
    if args.identity == '-' and args.notary_profile:
        parser.error('Ad-hoc test builds cannot be notarized.')
    output = args.output.resolve()
    if output.exists():
        parser.error('Output path already exists; choose a new path.')
    run('swift', 'run', '--build-system', 'native', 'NanoleafChecks')
    run('swift', 'build', '--build-system', 'native', '-c', 'release', '--product', 'nanoleaf')
    with tempfile.TemporaryDirectory(prefix='nanoleaf-sign-') as temporary:
        stage = pathlib.Path(temporary)
        app = stage / 'Nanoleaf.app'
        contents = app / 'Contents'
        (contents / 'MacOS').mkdir(parents=True)
        shutil.copy2(ROOT / '.build/release/nanoleaf', contents / 'MacOS/nanoleaf')
        # Remove debug object paths before signing the distributed executable.
        run('/usr/bin/strip', '-S', str(contents / 'MacOS/nanoleaf'))
        info = plistlib.loads((ROOT / 'Support/Info.plist').read_bytes())
        info.update(CFBundleExecutable='nanoleaf', CFBundlePackageType='APPL',
                    CFBundleVersion=args.version, CFBundleShortVersionString=args.version, LSUIElement=True)
        (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
        signing = ['codesign', '--force', '--sign', args.identity]
        if args.identity != '-':
            signing += ['--options', 'runtime', '--entitlements', str(ROOT / 'Support/Entitlements.plist')]
            signing += ['--timestamp=none'] if args.self_signed else ['--timestamp']
        run(*signing, str(app))
        run('codesign', '--verify', '--strict', str(app))
        signature = subprocess.run(['codesign', '-dv', str(app)], capture_output=True, text=True, check=True).stderr
        if args.identity != '-' and not args.self_signed and 'Authority=Developer ID Application:' not in signature:
            raise SystemExit('Expected a Developer ID Application certificate; refusing to package another signing identity.')
        if args.notary_profile:
            submission = stage / 'notarization.zip'
            run('ditto', '--norsrc', '--noextattr', '-c', '-k', '--keepParent', str(app), str(submission))
            run('xcrun', 'notarytool', 'submit', str(submission), '--keychain-profile', args.notary_profile, '--wait')
            run('xcrun', 'stapler', 'staple', str(app))
            run('xcrun', 'stapler', 'validate', str(app))
            run('spctl', '--assess', '--type', 'execute', str(app))
            submission.unlink()
        for name in ['LICENSE', 'THIRD_PARTY_NOTICES.md', 'CALIBRATION.md']:
            shutil.copy2(ROOT / name, stage / name)
        shutil.copy2(ROOT / 'Scripts/install-release.sh', stage / 'install.sh')
        (stage / 'INSTALL.txt').write_text('Run ./install.sh from this extracted directory. Keep Nanoleaf.app intact.\n'
            'The installer copies it into ~/Library/Application Support/nanoleaf and installs a CLI symlink.\n'
            'Allow Nanoleaf.app in Accessibility and Location Services when prompted.\n'
            + ('LOCAL AD-HOC TEST BUILD: permissions may reset on updates.\n' if args.identity == '-' else 'Self-signed app; not Apple-notarized.\n' if args.self_signed else 'Developer ID signed app.\n'))
        output.parent.mkdir(parents=True, exist_ok=True)
        run('ditto', '--norsrc', '--noextattr', '-c', '-k', str(stage), str(output))
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(output.suffix + '.sha256').write_text(f'{digest}  {output.name}\n')
    print(output)

if __name__ == '__main__':
    main()
