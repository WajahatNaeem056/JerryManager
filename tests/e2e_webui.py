"""E2E: real WebUI in headless Chromium; window.ksu.exec is bridged to a sandbox copy of the module (real dash + real pif_config.sh)."""
import subprocess, os, shutil, tempfile, threading, http.server, functools, json, sys, time
from playwright.sync_api import sync_playwright

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.dirname(os.path.abspath(__file__))
T = tempfile.mkdtemp(); MOD = f'{T}/mod'; SD = f'{T}/sdcard'; DATA = f'{T}/data'
shutil.copytree(f'{REPO}/Jerry', MOD); os.makedirs(SD+'/Download/my pifs'); os.makedirs(DATA)
FP = 'google/komodo_beta/komodo:CANARY/ZP11.260918.007/16484274:user/release-keys'
open(f'{SD}/Download/pif.json','w').write(json.dumps({"FINGERPRINT":FP,"MANUFACTURER":"Google","MODEL":"Pixel 9 Pro XL","SECURITY_PATCH":"2026-10-05","DEVICE_INITIAL_SDK_INT":"34"}))
open(f'{SD}/Download/my pifs/space pif.prop','w').write(f'FINGERPRINT={FP.replace("komodo","tokay")}\nMANUFACTURER=Google\nMODEL=Pixel 9\n')
open(f'{SD}/Download/bad.json','w').write('{"FINGERPRINT": "x",}')
open(f'{SD}/Download/keybox.xml','w').write('<x/>')
shutil.copy(f'{MOD}/pif.prop', f'{DATA}/pif.prop')
ENV = dict(os.environ, JERRY_PIF_PROP=f'{DATA}/pif.prop', PIF_IMPORT_BACKUP_DIR=f'{DATA}/bak', PIF_IMPORT_WORK_ROOT=f'{DATA}/work')
calls = []
def run(cmd):
    cmd = cmd.replace('/data/adb/modules/JerryManager', MOD).replace('/sdcard', SD)
    calls.append(cmd)
    p = subprocess.run(['dash','-c',cmd], capture_output=True, text=True, env=ENV, timeout=30)
    return {'code': p.returncode, 'stdout': p.stdout.replace(SD,'/sdcard').replace(MOD,'/data/adb/modules/JerryManager'), 'stderr': p.stderr}

handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=f'{MOD}/webroot')
handler.log_message = lambda *a, **k: None
srv = http.server.ThreadingHTTPServer(('127.0.0.1', 8765), handler); threading.Thread(target=srv.serve_forever, daemon=True).start()

INIT = """window.ksu={exec:function(cmd,o,cb){window.__run(cmd).then(function(r){setTimeout(function(){window[cb](r.code,r.stdout,r.stderr)},0)})}};"""
res = []
def check(name, cond, extra=''):
    res.append(cond); print(('PASS ' if cond else 'FAIL ')+name, extra if not cond else '')

PG=None
def until(fn, t=8):
    end=time.time()+t
    while time.time()<end:
        try:
            if fn(): return True
        except Exception: pass
        PG.wait_for_timeout(150)  # keeps Playwright servicing the exposed ksu bridge
    return False
def term(page): return page.text_content('#pif-console') or ''
def pick(page, steps, expect_sel=None):
    page.click('#pif-import')
    page.wait_for_selector('md-dialog.fb-dialog .fb-row', timeout=8000)
    for nm in steps:
        page.locator('md-dialog.fb-dialog .fb-row', has_text=nm).first.click(); time.sleep(.4)

with sync_playwright() as p:
    b = p.chromium.launch(); pg = b.new_page(viewport={'width':400,'height':820})
    PG = pg; errs = []; pg.on('pageerror', lambda e: errs.append(str(e)))
    pg.expose_function('__run', run); pg.add_init_script(INIT)
    pg.goto('http://127.0.0.1:8765/index.html'); time.sleep(2.5)
    pg.evaluate('jerryNavSwitch(1)'); time.sleep(.8)   # Actions tab

    check('Import row visible on Actions tab', pg.is_visible('#pif-import'))
    check('Row title/desc text', 'Import fingerprint' in pg.inner_text('#pif-import') and 'Load a pif.json or pif.prop file' in pg.inner_text('#pif-import'))
    y = lambda s: pg.eval_on_selector(s, 'e=>e.getBoundingClientRect().top')
    check('Placed directly below PIF Settings, inside PIF Configs', y('#pif-settings-btn') < y('#pif-import') < y('#app-targeting-btn'))
    check('Same list container as PIF Settings', pg.evaluate("document.getElementById('pif-import').parentElement === document.getElementById('pif-settings-btn').parentElement"))
    check('No import row left inside PIF Settings page', pg.locator('#pif-settings-panel #pif-import').count()==0)
    pg.screenshot(path=OUT+'/shot1_row.png')

    # --- cancel: nothing changes
    before = open(f'{DATA}/pif.prop').read(); n_calls = len(calls)
    pg.click('#pif-import'); pg.wait_for_selector('md-dialog.fb-dialog .fb-row')
    pg.screenshot(path=''+OUT+'/shot2_browser.png')
    pg.click('#fb-cancel'); time.sleep(.5)
    check('Cancel leaves pif.prop untouched', open(f'{DATA}/pif.prop').read()==before)
    check('Cancel runs no import command', not any(' import ' in c for c in calls[n_calls:]))

    # --- filter only shows json/prop; keybox.xml hidden until Show all
    pg.click('#pif-import'); pg.wait_for_selector('md-dialog.fb-dialog .fb-row')
    pg.locator('md-dialog.fb-dialog .fb-row', has_text='Download').first.click(); time.sleep(.5)
    names = pg.locator('md-dialog.fb-dialog .fb-row-name').all_inner_texts()
    check('Browser lists pif.json, hides keybox.xml', 'pif.json' in names and 'keybox.xml' not in names, str(names))
    # --- invalid JSON rejected, config untouched
    pg.locator('md-dialog.fb-dialog .fb-row', has_text='bad.json').click(); pg.click('#fb-select'); until(lambda: 'Import failed' in term(pg))
    t = term(pg)
    check('Invalid JSON: error shown in terminal + toast', 'Import failed' in t and 'Malformed' in t and pg.locator('.pif-toast', has_text='Import failed').count()>=1, t)
    check('Invalid JSON: pif.prop unchanged', open(f'{DATA}/pif.prop').read()==before)
    check('Invalid JSON: no success message', 'Fingerprint imported' not in t)
    pg.screenshot(path=''+OUT+'/shot3_error.png')

    # --- valid pif.json
    pg.click('#pif-import'); pg.wait_for_selector('md-dialog.fb-dialog .fb-row')
    pg.locator('md-dialog.fb-dialog .fb-row', has_text='Download').first.click(); time.sleep(.5)
    pg.locator('md-dialog.fb-dialog .fb-row', has_text='pif.json').click(); pg.click('#fb-select'); until(lambda: 'Fingerprint imported' in term(pg))
    t = term(pg); cur = open(f'{DATA}/pif.prop').read()
    check('Valid pif.json: success in terminal', 'Fingerprint imported: Pixel 9 Pro XL' in t, t)
    check('Valid pif.json: pif.prop updated (backend file)', 'MODEL=Pixel 9 Pro XL' in cur and f'FINGERPRINT={FP}' in cur)
    check('Row subtitle shows imported device + file', 'Pixel 9 Pro XL' in pg.inner_text('#pif-import-desc') and 'pif.json' in pg.inner_text('#pif-import-desc'))
    pg.screenshot(path=''+OUT+'/shot4_success.png')
    # existing backend + existing UI keep working (open the PIF Settings page now)
    pg.evaluate('openPifSettings()'); pg.wait_for_timeout(800)
    pg.click('#pif-view'); until(lambda: 'Pixel 9 Pro XL' in term(pg))
    check('Existing "View pif.prop" shows imported config', 'Pixel 9 Pro XL' in term(pg))
    pg.wait_for_timeout(1500)  # let the post-import refresh() finish before touching a toggle
    sw = pg.locator('[data-pif=spoofBuild]'); st0 = sw.evaluate('e=>e.selected'); sw.click(); until(lambda: ('spoofBuild=%s' % ('false' if st0 else 'true')) in open(f'{DATA}/pif.prop').read())
    check('Existing spoof toggle still writes pif.prop', ('spoofBuild=%s' % ('false' if st0 else 'true')) in open(f'{DATA}/pif.prop').read())

    # --- valid pif.prop in a folder with a space in its name
    pg.evaluate('closePifSettings()'); pg.wait_for_timeout(500)
    pg.click('#pif-import'); pg.wait_for_selector('md-dialog.fb-dialog .fb-row')
    pg.locator('md-dialog.fb-dialog .fb-row', has_text='Download').first.click(); time.sleep(.5)
    pg.locator('md-dialog.fb-dialog .fb-row', has_text='my pifs').click(); time.sleep(.6)
    pg.locator('md-dialog.fb-dialog .fb-row', has_text='space pif.prop').click(); pg.click('#fb-select'); until(lambda: 'tokay_beta' in open(f'{DATA}/pif.prop').read()); until(lambda: 'Pixel 9' in term(pg).split('pif import space')[-1] and 'imported' in term(pg).split('pif import space')[-1])
    cur = open(f'{DATA}/pif.prop').read()
    check('Valid pif.prop (path with space) imported', 'MODEL=Pixel 9' in cur and 'tokay_beta' in cur and 'Fingerprint imported: Pixel 9' in term(pg))
    check('Toggle changed earlier is preserved through import', ('spoofBuild=%s' % ('false' if st0 else 'true')) in cur)
    check('Backups were created', len(os.listdir(f'{DATA}/bak'))>=2)

    # --- keybox browser (existing feature) still works with defaults
    pg.evaluate("window.jerryOpenFileBrowser(function(){})"); pg.wait_for_selector('md-dialog.fb-dialog .fb-row'); 
    pg.locator('md-dialog.fb-dialog .fb-row', has_text='Download').first.click(); time.sleep(.5)
    names = pg.locator('md-dialog.fb-dialog .fb-row-name').all_inner_texts()
    check('Default browser (keybox) still filters to .xml/.bak', 'keybox.xml' in names and 'pif.json' not in names, str(names))
    check('No JS errors on page', not errs, str(errs))
    b.close()
print(f'---- {sum(res)}/{len(res)} passed'); sys.exit(0 if all(res) else 1)
