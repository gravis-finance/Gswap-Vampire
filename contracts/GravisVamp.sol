// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./uniswapv2/interfaces/IUniswapV2Pair.sol";
import "./uniswapv2/interfaces/IUniswapV2Factory.sol";
import "./uniswapv2/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "./interfaces/IMooniswap.sol";
import "./libraries/TransferHelper.sol";

/**
 * @dev Contract to convert liquidity from other market makers (Uniswap/Mooniswap) to our pairs.
 */
contract GravisVamp is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    uint constant LIQUIDITY_DEADLINE = 10 * 20; // 10 minutes in blocks, ~3 sec per block

    struct LPTokenInfo {
        address lpToken;
        uint16 tokenType; // Token type: 0 - uniswap (default), 1 - mooniswap
    }

    IERC20[] public allowedTokens; // List of tokens that we accept

    // Info of each third-party lp-token.
    LPTokenInfo[] public lpTokensInfo;

    IUniswapV2Router01 public ourRouter;

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event AllowedTokenAdded(address indexed token);
    event AllowedTokenRemoved(address indexed token);
    event LPTokenAdded(address indexed token, uint256 tokenType);
    event LPTokenChanged(address indexed oldToken, address indexed newToken, uint256 oldType, uint256 newType);
    event RouterChanged(address indexed oldRouter, address indexed newRouter);

    constructor(
        address[] memory _lptokens,
        uint8[] memory _types,
        address _ourrouter
    ) public {
        require(_lptokens.length > 0, "GravisVamp: _lptokens length should not be 0!");
        require(_lptokens.length == _types.length, "GravisVamp: array lengths should be equal");
        require(_ourrouter != address(0), "GravisVamp: _ourrouter address should not be 0");

        for (uint256 i = 0; i < _lptokens.length; i++) {
            lpTokensInfo.push(
                LPTokenInfo({lpToken: _lptokens[i], tokenType: _types[i]})
            );
        }
        ourRouter = IUniswapV2Router01(_ourrouter);
    }

    /**
     * @dev Returns length of allowed tokens private array
     */
    function getAllowedTokensLength() external view returns (uint256) {
        return allowedTokens.length;
    }

    function lpTokensInfoLength() external view returns (uint256) {
        return lpTokensInfo.length;
    }

    /**
     *  @dev Returns pair base tokens
     */
    function lpTokenDetailedInfo(uint256 _pid)
        external
        view
        returns (address, address)
    {
        require(_pid < lpTokensInfo.length, "GravisVamp: _pid should be less than lpTokensInfo");
        if (lpTokensInfo[_pid].tokenType == 0) {
            // this is uniswap
            IUniswapV2Pair lpToken = IUniswapV2Pair(lpTokensInfo[_pid].lpToken);
            return (lpToken.token0(), lpToken.token1());
        } else {
            // this is mooniswap
            IMooniswap lpToken = IMooniswap(lpTokensInfo[_pid].lpToken);
            IERC20[] memory t = lpToken.getTokens();
            return (address(t[0]), address(t[1]));
        }
    }

    /**
     * @dev Adds new entry to the list of allowed tokens (if it is not exist yet)
     */
    function addAllowedToken(address _token) external onlyOwner {
        require(_token != address(0),"GravisVamp: _token address should not be 0");

        for (uint256 i = 0; i < allowedTokens.length; i++) {
            if (address(allowedTokens[i]) == _token) {
                require(false, "GravisVamp: Token already exists!");
            }
        }
        emit AllowedTokenAdded(_token);
        allowedTokens.push(IERC20(_token));
    }

    /**
     * @dev Remove entry from the list of allowed tokens
     */
    function removeAllowedToken(uint _idx) external onlyOwner {
        require(_idx < allowedTokens.length, "GravisVamp: _idx out of range");

        emit AllowedTokenRemoved(address(allowedTokens[_idx]));
        delete allowedTokens[_idx];
    }

    /**
     * @dev Adds new entry to the list of convertible LP-tokens
     */
    function addLPToken(address _token, uint16 _tokenType)
        external
        onlyOwner
        returns (uint256)
    {
        require(_token != address(0),"GravisVamp: _token address should not be 0!");
        require(_tokenType < 2,"GravisVamp: wrong token type!");

        for (uint256 i = 0; i < lpTokensInfo.length; i++) {
            if (lpTokensInfo[i].lpToken == _token) {
                require(false, "GravisVamp: Token already exists!");
            }
        }
        lpTokensInfo.push(
            LPTokenInfo({lpToken: _token, tokenType: _tokenType})
        );
        emit LPTokenAdded(_token, _tokenType);
        return lpTokensInfo.length;
    }

    /**
     * @dev Remove entry from the list of convertible LP-tokens
     */
    function changeLPToken(uint _idx, address _token, uint16 _tokenType) external onlyOwner {
        require(_idx < lpTokensInfo.length, "GravisVamp: _idx out of range");
        require(_token != address(0), "GravisVamp: _token address should not be 0!");
        require(_tokenType < 2, "GravisVamp: wrong tokenType");

        emit LPTokenChanged(lpTokensInfo[_idx].lpToken, _token, lpTokensInfo[_idx].tokenType, _tokenType);
        lpTokensInfo[_idx].lpToken = _token;
        lpTokensInfo[_idx].tokenType = _tokenType;
    }

    /**
     * @dev Change router address
     */
    function changeRouter(address _newRouter) external onlyOwner {
        require(_newRouter != address(0), "New Router address is wrong");

        emit RouterChanged(address(ourRouter), _newRouter);
        ourRouter = IUniswapV2Router01(_newRouter);
    }

    // Deposit LP tokens to us
    /**
     * @dev Main function that converts third-party liquidity (represented by LP-tokens) to our own LP-tokens
     */
    function deposit(uint256 _pid, uint256 _amount) external {
        require(_pid < lpTokensInfo.length, "GravisVamp: _pid out of range!");

        if (lpTokensInfo[_pid].tokenType == 0) {
            _depositUniswap(_pid, _amount);
        } else if (lpTokensInfo[_pid].tokenType == 1) {
            _depositMooniswap(_pid, _amount);
        } else {
            return;
        }
        emit Deposit(msg.sender, lpTokensInfo[_pid].lpToken, _amount);
    }

    /**
     * @dev Actual function that converts third-party Uniswap liquidity (represented by LP-tokens) to our own LP-tokens
     */
    function _depositUniswap(uint256 _pid, uint256 _amount) internal {
        IUniswapV2Pair lpToken = IUniswapV2Pair(lpTokensInfo[_pid].lpToken);

        // check pair existance
        IERC20 token0 = IERC20(lpToken.token0());
        IERC20 token1 = IERC20(lpToken.token1());

        // transfer to us
            TransferHelper.safeTransferFrom(address(lpToken), address(msg.sender), address(lpToken), _amount);

        // get liquidity
        (uint256 amountIn0, uint256 amountIn1) = lpToken.burn(address(this));

        _addLiquidity(
            address(token0),
            address(token1),
            amountIn0,
            amountIn1,
            msg.sender
        );
    }

    function _addLiquidity(
        address _token0,
        address _token1,
        uint256 _amount0,
        uint256 _amount1,
        address _receiver
    ) internal {
        TransferHelper.safeApprove(_token0, address(ourRouter), _amount0);
        TransferHelper.safeApprove(_token1, address(ourRouter), _amount1);

        (uint256 amountOut0, uint256 amountOut1, ) =
            ourRouter.addLiquidity(
                address(_token0),
                address(_token1),
                _amount0,
                _amount1,
                0,
                0,
                _receiver,
                block.timestamp + LIQUIDITY_DEADLINE
            );

        // return the change
        if (amountOut0 < _amount0) { // consumed less tokens than given
            TransferHelper.safeTransfer(
                _token0,
                address(msg.sender),
                _amount0.sub(amountOut0)
            );
        }

        if (amountOut1 < _amount1) { // consumed less tokens than given
            TransferHelper.safeTransfer(
                _token1,
                address(msg.sender),
                _amount1.sub(amountOut1)
            );
        }
        TransferHelper.safeApprove(_token0, address(ourRouter), 0);
        TransferHelper.safeApprove(_token1, address(ourRouter), 0);
    }

    /**
     * @dev Actual function that converts third-party Mooniswap liquidity (represented by LP-tokens) to our own LP-tokens
     */
    function _depositMooniswap(uint256 _pid, uint256 _amount) internal {
        IMooniswap lpToken = IMooniswap(lpTokensInfo[_pid].lpToken);
        IERC20[] memory t = lpToken.getTokens();

        // check pair existance
        IERC20 token0 = IERC20(t[0]);
        IERC20 token1 = IERC20(t[1]);

        // transfer to us
        TransferHelper.safeTransferFrom(address(lpToken), address(msg.sender), address(this), _amount);

        uint256 amountBefore0 = token0.balanceOf(address(this));
        uint256 amountBefore1 = token1.balanceOf(address(this));

        uint256[] memory minVals = new uint256[](2);

        lpToken.withdraw(_amount, minVals);

        // get liquidity
        uint256 amount0 = token0.balanceOf(address(this)).sub(amountBefore0);
        uint256 amount1 = token1.balanceOf(address(this)).sub(amountBefore1);

        _addLiquidity(
            address(token0),
            address(token1),
            amount0,
            amount1,
            msg.sender
        );
    }

    /**
     * @dev Function checks for LP token pair availability. Return false if none exists
     */
    function isPairAvailable(address _token0, address _token1)
        external
        view
        returns (bool)
    {
        require(_token0 != address(0), "GravisVamp: _token0 address should not be 0!");
        require(_token1 != address(0), "GravisVamp: _token1 address should not be 0!");

        for (uint16 i = 0; i < lpTokensInfo.length; i++) {
            address t0 = address(0);
            address t1 = address(0);

            if (lpTokensInfo[i].tokenType == 0) {
              IUniswapV2Pair lpt = IUniswapV2Pair(lpTokensInfo[i].lpToken);
              t0 = lpt.token0();
              t1 = lpt.token1();
            } else if (lpTokensInfo[i].tokenType == 1) {
              IMooniswap lpToken = IMooniswap(lpTokensInfo[i].lpToken);

              IERC20[] memory t = lpToken.getTokens();

              t0 = address(t[0]);
              t1 = address(t[1]);
            } else {
                return false;
            }

            if (
                (t0 == _token0 && t1 == _token1) ||
                (t1 == _token0 && t0 == _token1)
            ) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Owner can transfer out any accidentally sent ERC20 tokens
     */
    function transferAnyERC20Token(
        address tokenAddress,
        address beneficiary,
        uint256 amount
    ) external onlyOwner returns (bool success) {
        require(tokenAddress != address(0), "GravisVamp: Token address cannot be 0");

        return IERC20(tokenAddress).transfer(beneficiary, amount);
    }
}
