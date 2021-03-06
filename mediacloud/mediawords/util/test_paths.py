import tempfile

from nose.tools import assert_raises

from mediawords.util.paths import *


def test_mc_root_path():
    root_path = mc_root_path()
    assert os.path.exists(root_path)
    assert os.path.isdir(root_path)
    assert os.path.isfile(os.path.join(root_path, 'mediawords.yml.dist'))


def test_mc_script_path():
    script_path = mc_script_path()
    assert os.path.exists(script_path)
    assert os.path.isdir(script_path)


def test_mkdir_p():
    temp_dir = tempfile.mkdtemp()

    test_dir = os.path.join(temp_dir, 'foo', 'bar', 'baz')
    assert os.path.isdir(test_dir) is False

    mkdir_p(test_dir)
    assert os.path.isdir(test_dir) is True

    # Try creating again
    mkdir_p(test_dir)
    assert os.path.isdir(test_dir) is True


def test_resolve_absolute_path_under_mc_root():
    path = resolve_absolute_path_under_mc_root(path='.', must_exist=True)
    assert len(path) > 0

    # Path that exists
    path = resolve_absolute_path_under_mc_root(path='mediawords.yml', must_exist=True)
    assert len(path) > 0
    assert os.path.isfile(path) is True

    # Path that does not exist
    path = resolve_absolute_path_under_mc_root(path='TOTALLY_DOES_NOT_EXIST', must_exist=False)
    assert len(path) > 0
    assert os.path.isfile(path) is False


def test_relative_symlink():
    temp_dir = tempfile.mkdtemp()

    source_dir = os.path.join(temp_dir, 'src', 'a', 'b', 'c')
    mkdir_p(source_dir)
    with open(os.path.join(source_dir, 'test.txt'), 'w') as fh:
        fh.write('foo')

    dest_dir = os.path.join(temp_dir, 'dst', 'd', 'e')
    mkdir_p(dest_dir)
    dest_symlink = os.path.join(dest_dir, 'f')

    relative_symlink(source=source_dir, link_name=dest_symlink)

    assert os.path.exists(dest_symlink)
    assert os.path.lexists(dest_symlink)
    assert os.path.islink(dest_symlink)
    assert os.path.exists(os.path.join(dest_symlink, 'test.txt'))


def test_file_extension():
    assert file_extension('') == ''
    assert file_extension('test') == ''
    assert file_extension('test.zip') == '.zip'
    assert file_extension('/var/lib/test.zip') == '.zip'
    assert file_extension('../../test.zip') == '.zip'
    assert file_extension('./../../test.zip') == '.zip'
    assert file_extension('TEST.ZIP') == '.zip'
    assert file_extension('test.tar.gz') == '.gz'
    assert file_extension('TEST.TAR.GZ') == '.gz'


def test_lock_unlock_file():
    temp_dir = tempfile.mkdtemp()
    lock_file_path = os.path.join(temp_dir, 'test.lock')

    assert os.path.isfile(lock_file_path) is False
    lock_file(lock_file_path)
    assert os.path.isfile(lock_file_path) is True
    unlock_file(lock_file_path)
    assert os.path.isfile(lock_file_path) is False

    # Try locking twice, with timeout
    assert os.path.isfile(lock_file_path) is False
    lock_file(lock_file_path)
    assert os.path.isfile(lock_file_path) is True
    assert_raises(McLockFileException, lock_file, lock_file_path, 2)
    assert os.path.isfile(lock_file_path) is True
    unlock_file(lock_file_path)
    assert os.path.isfile(lock_file_path) is False

    # Try unlocking nonexistent file
    assert os.path.isfile(lock_file_path) is False
    assert_raises(McUnlockFileException, unlock_file, lock_file_path)
    assert os.path.isfile(lock_file_path) is False
