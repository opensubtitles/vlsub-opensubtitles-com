# Rewrite all commits to change author
git filter-branch --env-filter '
OLD_EMAIL="2ge@2ge.us"
CORRECT_NAME="OpenSubtitles"
CORRECT_EMAIL="admin@opensubtitles.org"

if [ "$GIT_COMMITTER_EMAIL" = "$OLD_EMAIL" ]
then
    export GIT_COMMITTER_NAME="$CORRECT_NAME"
    export GIT_COMMITTER_EMAIL="$CORRECT_EMAIL"
fi
if [ "$GIT_AUTHOR_EMAIL" = "$OLD_EMAIL" ]
then
    export GIT_AUTHOR_NAME="$CORRECT_NAME"
    export GIT_AUTHOR_EMAIL="$CORRECT_EMAIL"
fi
' --tag-name-filter cat -- --branches --tags

# Force push everything
git push --force --all origin
git push --force --tags origin

