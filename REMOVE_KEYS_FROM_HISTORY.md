# Commands to Remove Exposed API Keys from Git History

⚠️ **WARNING**: These commands rewrite git history. Only proceed if:
- You have backed up your repository
- You've notified all collaborators
- You understand that all collaborators will need to re-clone after you force push

## Option 1: Using git filter-branch (Built-in, slower but works)

### Step 1: Remove files from all branches and tags
```bash
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch android/app/google-services.json lib/firebase_options.dart" \
  --prune-empty --tag-name-filter cat -- --all
```

### Step 2: Clean up refs and optimize
```bash
git for-each-ref --format='delete %(refname)' refs/original | git update-ref --stdin
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

### Step 3: Force push to remote (⚠️ Rewrites history)
```bash
git push origin --force --all
git push origin --force --tags
```

---

## Option 2: Using git filter-repo (Recommended - faster, cleaner)

### Install git-filter-repo (if not already installed)
```bash
# Windows (using pip)
pip install git-filter-repo

# Or download from: https://github.com/newren/git-filter-repo
```

### Step 1: Remove the files
```bash
git filter-repo --path android/app/google-services.json --invert-paths
git filter-repo --path lib/firebase_options.dart --invert-paths
```

### Step 2: Force push to remote (⚠️ Rewrites history)
```bash
git push origin --force --all
git push origin --force --tags
```

---

## Option 3: Using BFG Repo-Cleaner (Fastest for large repos)

### Download BFG
Download from: https://rtyley.github.io/bfg-repo-cleaner/

### Step 1: Clone a fresh copy (BFG needs a bare repo)
```bash
git clone --mirror https://github.com/baartzr/actionmail.git actionmail.git
```

### Step 2: Remove the files
```bash
java -jar bfg.jar --delete-files google-services.json actionmail.git
java -jar bfg.jar --delete-files firebase_options.dart actionmail.git
```

### Step 3: Clean up
```bash
cd actionmail.git
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

### Step 4: Push back
```bash
git push
```

---

## After Force Pushing

### For Collaborators:
All collaborators must:
1. **Back up their work** (commit or stash)
2. Delete their local repository
3. Clone fresh:
   ```bash
   git clone https://github.com/baartzr/actionmail.git
   ```

### Verify Removal:
Check that the files are no longer in history:
```bash
git log --all --full-history -- android/app/google-services.json
git log --all --full-history -- lib/firebase_options.dart
```
(These should return no results)

### Check on GitHub:
Visit: https://github.com/baartzr/actionmail/blob/main/android/app/google-services.json
(Should show 404 - file not found)

---

## Important Notes

1. **GitHub's cache**: GitHub may still show the files in search results for a while (hours/days). The files are removed from git history but search indexing takes time.

2. **Branches**: Make sure to clean all branches:
   ```bash
   git branch -a  # List all branches
   # Run filter-branch/filter-repo on each branch, or use --all flag
   ```

3. **Tags**: Make sure tags are cleaned too (use `--tags` in commands above)

4. **Backup**: Always create a backup first:
   ```bash
   git clone --mirror https://github.com/baartzr/actionmail.git actionmail-backup.git
   ```

