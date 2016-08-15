function [d_new, d_old] = testmex(sigma, nS, Nnew, Nold, SNew, SOld, X)
% calculate log odds
% function used as a basis for Luigi to code up C code!
%
% ================ INPUT VARIABLES ====================
% SIGMA: memory noise. [scalar] (double)
% NS: number of samples of SNew and SOld. [scalar] (integer)
% NNEW: number of new words. [scalar] (integer)
% NOLD: number of old words. [scalar] (integer)
% SNEW: new words across S simulations. [Nnew*nS,1,M] (double)
% SOLD: old words across S simulations. [Nold*nS,TEMP] (double)
% X: noisy memories. [Nold,M] (double)
% 
% ================ OUTPUT VARIABLES ==================
% D_NEW: log odds of new trials. [Nnew*nS,1,nS] (double)
% D_OLD: log odds of old trials. [1,1,1] (double)
%

M = size(SNew,3);   % Number of features

J = 1/sigma.^2+1;
d_new = M/2*log(1+1/sigma^2) + 0.5*sum(SNew.^2,2) + log(squeeze(mean(exp(-0.5*J*...
    sum((permute(repmat(SNew,[1,1,Nold]), [3,2,1]) - repmat(X/J/sigma^2,[1,1,Nnew*nS])).^2,2)))));
d_old = M/2*log(1+1/sigma^2) + 0.5*sum(SOld.^2,2) + log(squeeze(mean(exp(-0.5*J*...
   sum((permute(repmat(SOld,[1,1,Nold]), [3,2,1]) - repmat(X/J/sigma^2,[1,1,Nold*nS])).^2,2)))));