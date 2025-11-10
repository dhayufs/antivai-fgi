<?php
// ============================================================
// FGI AntivAI Security Dashboard (FINAL STABLE RELEASE)
// ============================================================

$cfg_file = "/usr/local/cwp/.conf/antivai.ini";
$quar = "/var/quarantine/antivai";
$restore = "/root/antivai_restored";

// Load config
$cfg = [];
if (file_exists($cfg_file)) {
  foreach (file($cfg_file) as $line) {
    if (strpos($line, "=") !== false) {
      list($k,$v)=explode("=",trim($line),2);
      $cfg[$k]=$v;
    }
  }
}

// Redirect back to dashboard
function back(){ echo '<script>window.location="index.php?module=antivai&toast=1";</script>'; exit; }

// ================= ACTIONS =================
if(isset($_GET['action'])){
  switch($_GET['action']){
    case "start":   @shell_exec("systemctl start antivai-watcher"); back();
    case "stop":    @shell_exec("systemctl stop antivai-watcher"); back();
    case "restart": @shell_exec("systemctl restart antivai-watcher"); back();
    case "testalert":
      if(!empty($cfg['TELEGRAM_BOT']) && !empty($cfg['TELEGRAM_CHAT'])){
        $msg=urlencode("✅ AntivAI Test Alert OK");
        @shell_exec("curl -s -X POST \"https://api.telegram.org/bot{$cfg['TELEGRAM_BOT']}/sendMessage\" -d chat_id=\"{$cfg['TELEGRAM_CHAT']}\" -d text=\"$msg\"");
      }
      back();
  }
}

if(isset($_GET['restore'])){
  $f=basename($_GET['restore']);
  if(file_exists("$quar/$f")){
    @mkdir($restore,0755,true);
    @rename("$quar/$f","$restore/$f");
  }
  back();
}

if(isset($_GET['delete'])){
  $f=basename($_GET['delete']);
  if(file_exists("$quar/$f")) unlink("$quar/$f");
  back();
}

// ============== SAVE CONFIG ==============
if(isset($_POST['savecfg'])){
  file_put_contents($cfg_file,$_POST['newcfg']);
  @shell_exec("systemctl restart antivai-watcher");
  back();
}

// ============== SAVE WHITELIST ==============
if(isset($_POST['savewl'])){
  $clean=str_replace(["\r","\n"],["",";"],trim($_POST['wl']));
  $data=file($cfg_file);
  $out="";
  foreach($data as $line){
    if(strpos($line,"WHITELIST=")===0) $out.="WHITELIST=$clean\n";
    else $out.=$line;
  }
  file_put_contents($cfg_file,$out);
  @shell_exec("systemctl restart antivai-watcher");
  back();
}

// ============== QUARANTINE LIST ==============
$files = is_dir($quar)? scandir($quar) : [];
usort($files,function($a,$b){return @filemtime("$quar/$b")-@filemtime("$quar/$a");});
?>

<div class="container-fluid">
<h3 class="mt-3 mb-4"><span class="icon16 icomoon-icon-shield"></span> FGI AntivAI Security</h3>

<?php if(isset($_GET['toast'])): ?>
<style>
#toast{position:fixed;top:20px;right:20px;background:#28a745;color:#fff;padding:12px 16px;border-radius:6px;box-shadow:0 3px 12px rgba(0,0,0,.3);z-index:9999;opacity:0;transition:.35s;}
#toast.show{opacity:1;}
</style>
<div id="toast">✅ Berhasil diproses</div>
<script>
setTimeout(()=>document.getElementById('toast').classList.add('show'),200);
setTimeout(()=>document.getElementById('toast').classList.remove('show'),3500);
</script>
<?php endif; ?>

<div class="card p-3 mb-4">
<h4>Watcher Control</h4>
<a class="btn btn-success btn-sm" href="index.php?module=antivai&action=start">▶ Start</a>
<a class="btn btn-danger btn-sm" href="index.php?module=antivai&action=stop">⏹ Stop</a>
<a class="btn btn-warning btn-sm" href="index.php?module=antivai&action=restart">🔄 Restart</a>
<a class="btn btn-info btn-sm" href="index.php?module=antivai&action=testalert">📲 Test Telegram</a>
</div>

<div class="card p-3 mb-4">
<h4>Quarantine Manager</h4>
<table class="table table-striped">
<tr><th>Filename</th><th>Size</th><th>Date</th><th>Action</th></tr>
<?php foreach($files as $f): if($f=="."||$f=="..") continue; ?>
<tr>
<td><?php echo htmlspecialchars($f); ?></td>
<td><?php echo filesize("$quar/$f"); ?> B</td>
<td><?php echo date("Y-m-d H:i:s",filemtime("$quar/$f")); ?></td>
<td>
<a class="btn btn-sm btn-primary" href="index.php?module=antivai&restore=<?php echo urlencode($f); ?>">♻ Restore</a>
<a class="btn btn-sm btn-danger" href="index.php?module=antivai&delete=<?php echo urlencode($f); ?>" onclick="return confirm('Hapus permanen?')">🗑 Delete</a>
</td>
</tr>
<?php endforeach; ?>
</table>
</div>

<div class="card p-3 mb-4">
<h4>Watcher Log (Realtime)</h4>
<pre style="background:#111;color:#0f0;padding:10px;max-height:220px;overflow:auto;"><?php @system("sudo /usr/bin/tail -n 80 /var/log/antivai-watcher.log"); ?></pre>
</div>

<div class="card p-3 mb-4">
<h4>AI Analysis Log</h4>
<pre style="background:#111;color:#0ff;padding:10px;max-height:220px;overflow:auto;"><?php @system("sudo /usr/bin/tail -n 80 /var/log/antivai-openai.log"); ?></pre>
</div>

<div class="card p-3 mb-4">
<h4>Edit antivai.ini</h4>
<form method="post">
<textarea name="newcfg" style="width:100%;height:240px;border-radius:6px;"><?php echo htmlspecialchars(file_get_contents($cfg_file)); ?></textarea>
<button class="btn btn-primary btn-sm mt-2" name="savecfg">💾 Save & Restart</button>
</form>
</div>

<div class="card p-3 mb-4">
<h4>Edit Whitelist</h4>
<form method="post">
<textarea name="wl" style="width:100%;height:140px;border-radius:6px;"><?php echo str_replace(";","\n",$cfg['WHITELIST']); ?></textarea>
<button class="btn btn-primary btn-sm mt-2" name="savewl">💾 Save & Restart</button>
</form>
</div>

</div>